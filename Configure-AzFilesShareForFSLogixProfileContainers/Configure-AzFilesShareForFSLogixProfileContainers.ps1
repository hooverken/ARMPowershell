# Configure-AzFilesPermissionsForFSLogixProfileContainers.ps1
# by Ken Hoover <ken dot hoover at microsoft dotcom>
# Original version April 2021
# Last update Jul 2023

# This script configures an Azure Files share to hold FSLogix profiles
# If the share name specified is not present on the storage account, it will be created.

# Prerequisites:
#
#  - The local system must have network visibility to the storage account on port 445
#  - Powershell 7 is required

# CHANGELOG
# 19 May 2021 : Detect if shared-key access is disabled and warn/exit if this is the case.  This breaks the NTFS
#               permissions work that is necessary.
# 10 Jun 2022 : Fix permissions for users in the created share to better align with FSLogix example.
# 20 Sep 2022 : Powershell 7+ is now required
#               Significant logic simplification to remove dependencies - now only three Az module components needed
#               Automatic install of needed Az modules if it's not present
#               Storage account name length validated (finally) at the parameter level
#               Improved checking of runtime prerequisites
#               Improved handling of IAM role assignments and drive mapping
# 29 Sep 2022 : (BUGFIX) NTFS permissions were not properly set for the Profile share's NTFS ACL (Issue #6)
#               Gracefully deal with pre-existing SMB mappings to same server - unlikely but possible, especially when testing
# 27 Feb 2023 : (logic fix) Simpler logic for checking if a SMB mapping to the storage account already exists
# 23 Mar 2023 : (BUGFIX) Force UPN suffix for user in context to lowercase when matching to avoid issues with AAD domain name check
# 05 Jul 2023 : Clean up logic and improve error output related to verification that user domain is also one of the tenant's domains.
<#
.SYNOPSIS

This script configures an Azure Files share for use with FSLogix profile containers.

.DESCRIPTION

This script configures an Azure Files share for use with FSLogix profile containers with permissions as described in the FSLogix documentation https://learn.microsoft.com/en-us/fslogix/fslogix-storage-config-ht.
    
To use it, follow these steps:

1. Log into a workstation which has network visibility to the selected Azure storage account on port 445/TCP

2. Connect to Azure using Connect-AzAccount and use Select-AzSubscription to switch context to the subscription where the storage account is located.

3. Run this script with the four required parameters.

.PARAMETER storageAccountName

The name of the storage account to configure.  The storage account must exist and have a name which is 15 characters or less in length to avoid legacy NetBIOS naming issues.

.PARAMETER profileShareName

The name of the file share to configure.  If the share does not exist, it will be created.  If the share name provided has mixed-case characters it will be converted to all-lowercase as required by Azure Files.

.PARAMETER ShareAdminGroupName

The name of an Azure AD group which will be granted full control of the share.  This group must already exist in Azure AD and will be assigned the "Storage File Data SMB Share Elevated Contributor" role on the specificd share.

.PARAMETER ShareUserGroupName

The name of an Azure AD group which will be granted basic read/write access to the share.  This group must already exist in Azure AD and will be assigned the IAM role "Storage File Data SMB Share Contributor" on the specified share.

.EXAMPLE

    .configure-AzFilesShareForFSLogixProfileContainers.ps1 -storageAccountName "myaccount" -profileShareName "fslogix" -ShareAdminGroupName "FSLogixAdmins" -ShareUserGroupName "FSLogixUsers"


.LINK
    https://www.github.com/hooverken/ARM-Powershell
#>


#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][ValidateLength(1,15)][string]$storageAccountName,     # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$profileShareName,       # The name of the profiles share.  The share will be created if it doesn't exist.
    [Parameter(mandatory = $true)][string]$ShareAdminGroupName,    # the name of an AD group which will have elevated access to the profile share
    [Parameter(mandatory = $true)][string]$ShareUserGroupName      # the name of an AD group which will have normal access to the profile share
)

# Verify that the Az modules we need are installed.  If not, install any midding ones.

Write-Verbose ("Verifying that the necessary Azure Powershell modules are present.")
$requiredModules = @("Az.Accounts", "Az.Storage", "Az.Resources")
$requiredModules | ForEach-Object {
    if (-not (Get-Module -Name $_ -ListAvailable)) {
        Write-Verbose ("Module $_ is not installed.  Installing it now.")
        Install-Module -Name $_ -Force -Scope CurrentUser
    }
}

# Make sure we are connected to Azure
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("You must connect to Azure with Connect-AzAccount before running this script.")
    Connect-AzAccount
    $currentContext = Get-Azcontext -ErrorAction SilentlyContinue
    if ($null -eq $currentContext) {
        Write-Error "No Azure context present.  Please verify that you have authenticated correctly using Connect-AzAccount"
        exit
    }
} else { 
    Write-Verbose ("Connected to Subscription " + $currentContext.Subscription.Id + " as " + $currentContext.Account.Id)
}

# If the user authenticated to Azure using a SP then the account name will be a GUID (the application ID)
# This won't work for this script so we need to catch this condition and exit if true.
$guidMatchRegEx = "^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$"
if ($currentContext.Account.Id -match $guidMatchRegEx) {
    Write-Warning "This script requires that you connect to Azure using a user account and not a service principal."
    exit
}

# This verifies that the user's UPN suffix is in the list of domains for the tenant.
# A mismatch here can break AD lookups.
$userdomain = $currentContext.Account.Id.split('@')[1].tolower()  # UPN suffix of the authenticated user.
if ($tenantinfo = (Get-AzTenant -ErrorAction SilentlyContinue)) {
    if (!($tenantinfo.Domains.Contains($userdomain)) ) {
        Write-Warning "User's UPN suffix ($userdomain) is not in the list of verified domains for the current tenant. Cannot proceed."
        exit
    } else {
        Write-Verbose ("Connection to AAD tenant name " + (Get-AzTenant | Where-Object { $_.domains.contains($userdomain)}).name  + " verified.")
    }
} else {
    Write-Warning "Get-AzTenant failed while validating AAD domains. Cannot proceed."
    exit
}

# Confirm that the storage account specified actually exists, that we can connect to it and grab the name of the RG that it's in.  
# Yes this is slow but this way means we don't need to ask the user for the storage account's RG name as a parameter
# We can get away with this because storage account names must be globally unique.
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }
if ($storageAccount) {
    write-verbose ("Storage account $storageAccountName is in Resource Group " + $storageaccount.ResourceGroupName)
    if ($storageaccount.PrimaryEndpoints.file -match "//(.*)/") {
        $endpointFqdn = $matches[1]
        # Verify that we can connect to the storage account's file endpoint on port 445.
        if (Test-NetConnection -ComputerName $endpointFqdn -Port 445 -InformationLevel Quiet) {
            Write-Verbose ("Connectivity to $endpointFqdn on port 445/TCP confirmed.")
        } else {
            Write-Warning ("Unable to connect to $endpointFqdn on port 445/TCP.`n ** Please verify that the storage account exists, is accessible from this workstation and that the file service is enabled.")
            exit
        }
    } else {
        Write-Warning "No valid file endpoint found for $storageaccountName.  Make sure that the file service is enabled on the storage account."
        exit
    }
} else {
    Write-Warning ("Storage account $storageAccountName not found in subscription ID " + $currentContext.Subscription + ".")
    exit
}

# Verify that the storage account does not have key AuthN disabled.  
# If it's disabled it will break the ACL-setting procedure used by this script.
# Ref: https://docs.microsoft.com/en-us/azure/storage/common/shared-key-authorization-prevent?tabs=portal
if ($false -eq $storageaccount.AllowSharedKeyAccess) {
    Write-Warning ("Storage account " + $storageAccount.StorageAccountName + " is configured to deny shared key access.")
    Write-Warning ("Please enable shared key access to this account before running this script.")
    Write-Warning ("After this script runs successuflly you can disable shared key access again.")
    exit
}

# Verify that the storage account is configured to use AD Authentication (either ADDS or AzureAD Kerberos)
$adAuthenticationType = $storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions
if ((($adAuthenticationType -eq "AD") -or ($adAuthenticationType -eq "AADKERB")) -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account $storageAccountName is configured to use AD domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("Storage account $storageAccountName is not configured for ADDS authentication.  Exiting.")
    exit
}

# Verify that the AAD group names provided actually exist and grab their object ID's for later.
# Elevated Contributor role (admins)
if (-not ($elevatedContributorGroupObjectId = (Get-AzADGroup -DisplayName $ShareAdminGroupName -ErrorAction SilentlyContinue).Id)) {
    Write-Warning ("Group $ShareAdminGroupName does not exist.  Please create this group before running this script.")
    exit
} else {
    Write-Verbose ("Group $ShareAdminGroupName exists with object ID $elevatedContributorGroupObjectId.")
}

# Contributor role (normal users)
if (-not ($contributorGroupObjectId = (Get-AzADGroup -DisplayName $ShareUserGroupName -ErrorAction SilentlyContinue).Id)) {
    Write-Warning ("Group $shareUserGroupName does not exist.  Please create this group before running this script.")
    exit
} else {
    Write-Verbose ("Group $shareUserGroupName exists with object ID $contributorGroupObjectId.")
}

########################## END OF SETUP/PREREQ CHECKING ############################

#  We've checked everyting we can think of so let's get to work.

### Setting up the file share ###

Write-verbose ("Setting storage context for role assignment.")

$storageContext = New-AzStorageContext -StorageAccountName $storageaccount.StorageAccountName `
                        -StorageAccountKey (get-AzStorageAccountKey `
                        -ResourceGroupName $storageAccount.resourcegroupname `
                        -Name $storageAccount.StorageAccountName)[0].Value

# Check if the Profiles share exists.  If not, create it.
Write-Verbose ("Checking if share $profileShareName exists in storage account " + $storageAccount.StorageAccountName)
if (-not (get-AzStorageShare -Name $profileShareName -Context $storageContext -ErrorAction SilentlyContinue)) {
    write-verbose ("File share $profileShareName does not exist.  Creating new share.")
    New-AzStorageShare -Name $profileShareName -Context $storageContext | out-null
} else {
    write-verbose ("Share $profileShareName is present.")
}

### IAM Role Assignments ###

Write-Verbose ("Assigning IAM roles for the $profileShareName share.")

$ContributorRoleDefinitionName = "Storage File Data SMB Share Contributor"
$ElevatedContributorRoleDefinitionName = "Storage File Data SMB Share Elevated Contributor"

$scope = $storageAccount.Id + "/fileservices/default/fileshares/" + $profileShareName

# Check if role assignments exist before creating them.

$elevatedContributorRoleAssignments = Get-AzRoleAssignment -scope $scope -RoleDefinitionName $ElevatedContributorRoleDefinitionName
if (($null -ne $elevatedContributorRoleAssignments) -and ($elevatedContributorRoleAssignments.ObjectID.contains($elevatedContributorGroupObjectId))) {
    Write-Verbose ("Role assignment $ElevatedContributorRoleDefinitionName already exists for group $shareAdminGroupName.")
} else {
    Write-Verbose ("Assigning role $ElevatedContributorRoleDefinitionName to group `"$ShareAdminGroupName`".")
    New-AzRoleAssignment -ObjectId $elevatedContributorGroupObjectId -RoleDefinitionName $ElevatedContributorRoleDefinitionName -Scope $scope | out-null
}

$contributorRoleAssignments = Get-AzRoleAssignment -scope $scope -RoleDefinitionName $ContributorRoleDefinitionName
if (($null -ne $contributorRoleAssignments) -and ($contributorRoleAssignments.ObjectID.contains($contributorGroupObjectId))) {
    Write-Verbose ("Role assignment `"$ContributorRoleDefinitionName`" already exists for group `"$shareUserGroupName`".")
} else {
    Write-Verbose ("Assigning role `"$ContributorRoleDefinitionName`" to group `"$shareUserGroupName`".")
    New-AzRoleAssignment -ObjectId $contributorGroupObjectId -RoleDefinitionName $ContributorRoleDefinitionName -Scope $scope | Out-Null
}

### Setting the NTFS ACLS ###

# below needed for setting NTFS rights on file system - can also do manually
$ShareName		= $profileShareName
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName `
                                              -Name $storageAccount.StorageAccountName).value[0]


# Get the primary file endpoint for this storage account.
$fileEndpoint = $storageaccount.PrimaryEndpoints.file.split('/')[2]

# Check if we already have a connection open to the same destination (even if it's a different share).  If so, drop the connection.
Write-Verbose ("Checking if there are any existing drive mappings to the same endpoint.")
Get-SmbMapping | ForEach-Object {
    if ($_.RemotePath.contains($fileEndpoint)) {
        Write-Verbose ("Disconnecting existing SMB mount to " + $_.RemotePath)
        Remove-SmbMapping -RemotePath $_.RemotePath -Force
    }
}

$MapPath = "\\"+$fileEndpoint + "\" +$ShareName  # should work foir all clouds

# Find an unused drive letter to map to the file share
$unusedDriveLetters = [Char[]](90..65) | Where-Object { (Test-Path "${_}:\") -eq $false }
$driveLetter = $unusedDriveLetters[0] + ":"  # using the first one

write-verbose ("Mounting $MapPath")
$result = new-smbmapping -LocalPath $driveLetter -RemotePath $MapPath -UserName $storageAccountName -Password $storageAccountKey -Persistent $false

if (!($result.status -eq "OK")) {
    Write-error "Attempt to map path $MapPath failed. Result was `n "
    write-host $Error[0]
    $result
    exit
}

Write-verbose ("Successfully mounted $MapPath as drive $driveLetter")

# Get the NTFS ACL on the root of the shared volume
$acl = Get-Acl $driveLetter

# IMPORTANT:  Theis script sets permissions to match the suggested model at this link
# https://learn.microsoft.com/en-us/fslogix/fslogix-storage-config-ht

# As noted on the linked page above, there are lots of ways to do NTFS-level security for FSLogix Profiles.
# The general idea is that you want to allow for users to create their own profiles, but you want 
# to make sure that people don't have the ability to touch VHD's created by other users while 
# preserving the rights of Admins to manage the share.

# icacls <mounted-drive-letter>: /grant <user-email>:(M)
# icacls <mounted-drive-letter>: /grant "Creator Owner":(OI)(CI)(IO)(M)

Write-Verbose ("... Removing `"NT AUTHORITY\Authenticated Users`"" )
$authenticatedUsersWellKnownSID = "S-1-5-11"  # the well-known SID for "Authenticated Users"
$principal = New-Object System.Security.Principal.SecurityIdentifier($authenticatedUsersWellKnownSID)
$identityReference = $principal.Translate([System.Security.Principal.NTAccount])
$acl.purgeAccessRules($identityReference)

# remove write perms for the built-in "Users" group
Write-Verbose ("... Removing BUILTIN\Users")
$builtinUsersWellKnownSID = "S-1-5-32-545"  # the well-known SID for builtin\users
$principal = New-Object System.Security.Principal.SecurityIdentifier($builtinUsersWellKnownSID)
$identityReference = $principal.Translate([System.Security.Principal.NTAccount])
$acl.purgeAccessRules($identityReference)

write-verbose ("... Setting new rule for BUILTIN\Users (modify, this folder only).")
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "Users", "Modify,Synchronize", "None", "None", "Allow"
$acl.SetAccessRule($rule)

# CREATOR OWNER / Subfolders and Files Only / Modify
write-verbose ("... Setting CREATOR OWNER (modify, subfolders and files only).")
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "CREATOR OWNER", "Modify,Synchronize", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)

# we're done messing with the ACL so we can write it back to the volume
$result = $acl | Set-Acl -Path $driveLetter

Write-Verbose ("Disconnecting from file share.")
Remove-SmbMapping -LocalPath $driveLetter -Force | out-null

Write-Verbose ("Execution complete.")