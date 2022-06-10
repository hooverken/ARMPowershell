# Configure-AzFilesPermissionsForFSLogixProfileContainers.ps1
# by Ken Hoover <ken dot hoover at microsoft dotcom>
# Original version April 2021

# This script does the IAM role assignments and NTFS permission configuration on an Azure Files share to prepare 
# it for use with FSLogix.

# If the share name specified is not present on the storage account, it will be created.

# Prerequisites:
#
#  Make sure that you're working with a domain-joined VM
#  AD Powershell module is installed and that current user can access/read AD
#  AzureAdPreview module is installed and connected to the proper directory tenant
#  Az module is installed and connected to the proper Azure context (e.g. subscription)

# CHANGELOG
# 19 May 2021 : Detect if shared-key access is disabled and warn/exit if this is the case.  This breaks the NTFS
#               permissions work that is necessary.
# 10 Jun 2022 : Fix permissions for users in the created share to align with FSLogix recommendations.


[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,     # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$profileShareName,       # The name of the profiles share.  The share will be created if it doesn't exist.
    [Parameter(mandatory = $true)][string]$ShareAdminGroupName,    # the name of an AD group which will have elevated access to the profile share
    [Parameter(mandatory = $true)][string]$ShareUserGroupName      # the name of an AD group which will have normal access to the profile share
)

# Make sure we are connected to Azure
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    if (get-command Connect-AzAccount) {
        Write-Verbose ("Not connected to Azure.  Please log in.")
        Connect-AzAccount
    } else {
        write-warning ("You must connect to Azure with Connect-AzAccount before running this script.")
        exit
    }
} else {
    Write-Verbose ("Connection to Azure Confirmed.")
}

# Make sure we're connected to Azure AD
if ($null -eq (Get-AzureADTenantDetail -ErrorAction SilentlyContinue )) {
    if (get-command Connect-AzureAd) {
        Write-Verbose ("Not connected to Azure.  Please log in with Connect-AzureAD.")
        Connect-AzAccount
    } else {
        write-warning ("You must connect to Azure with Connect-AzAccount before running this script.")
        exit
    }
} else {
    Write-Verbose ("Connection to Azure AD tenant " + (Get-AzureADTenantDetail).ObjectId + " verified.")
}


# Confirm that the storage account specified actually exists, that we can connect to it and grab the name of the 
# RG that it's in.  Yes this is inefficient but this way we don't need to bug the user for the storage account's
# RG name.
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }

if ($storageAccount) {
    # Grab the RG name that the storage account is in since we'll need it.
    $storageAccountRGName = $storageaccount.ResourceGroupName
    write-verbose "$storageAccountName is in Resource Group $storageAccountRGName."

    # Verify that we can connect to the storage account's files endpoint on port 445
    Write-Verbose ("Testing connectivity to " + $storageAccount.PrimaryEndpoints.File + " on port TCP/445...")
    if ($storageAccount.PrimaryEndpoints.File -match '\/\/(\S+)\/') {  # Matches the fqdn portion of the URL
        $filesEndpoint = $Matches[1]
        if (Test-NetConnection -port 445 -ComputerName $filesEndpoint -InformationLevel Quiet) {
            write-verbose ("Connection test to $filesEndpoint on port 445/TCP successful.")
        } else {
            write-warning ("Unable to connect to $filesEndpointFqdn on port TCP/445.")
            exit 
        }
    }
} else {
    Write-Warning ("Storage account $storageAccountName not found.")
    exit
}

# Verify that the storage account does not have key AuthN disabled.
# Ref: https://docs.microsoft.com/en-us/azure/storage/common/shared-key-authorization-prevent?tabs=portal
if ($false -eq $storageaccount.AllowSharedKeyAccess) {
    Write-Warning "Storage account " + $storageAccount.StorageAccountName + " is configured to prevent shared key access."
    Write-Warning "Please enable shared key access to this account before running this script."
    exit 
}

# Verify that the storage account is configured for ADDS Authentication
# $storageaccount = Get-AzStorageAccount -ResourceGroupName $storageAccountRGName -Name $storageAccountName

if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account $storageAccountName is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("Storage account $storageAccountName is not configured for ADDS authentication.  Exiting.")
    exit 
}

# Configuring IAM roles on the Azure Files share as required for FSLogix

#  Add Share-level permissions as per https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-assign-permissions
#
#  Users should have "Storage File Data SMB Share Contributor" and Admins "Storage File Data SMB Share Elevated Contributor"  
#

Write-verbose ("Setting storage context for role assignment...")

$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName `
                        -StorageAccountKey (get-AzStorageAccountKey -ResourceGroupName $storageAccountRGName `
                        -Name $storageAccountName)[0].Value

# Check if the Profiles share exists.  If not, create it.
Write-Verbose ("Checking if share $profileShareName exists in storage account $storageAccountName...")
if (!(get-AzStorageShare -Name $profileShareName -Context $storageContext -ErrorAction SilentlyContinue)) {
    write-verbose ("File share $profileShareName does not exist.  Creating new share $profileShareName...")
    New-AzStorageShare -Name $profileShareName -Context $storageContext
} else {
    write-verbose ("Share $profileShareName is present (good)")
}

Write-Verbose ("Assigning IAM roles for the $profileShareName share...")

if (Get-AdGroup -Identity $ShareAdminGroupName) {
    write-verbose ("Getting ObjectID for AAD group $ShareadminGroupName...")
    $filter = "Displayname eq '$ShareAdminGroupName'"
    $elevatedContributorObjectId = (Get-AzureADGroup -filter $filter).ObjectId
    if ($true -ne $?) {
        write-warning ( "Error retrieving information for group $ShareAdminGroupName.  Check the name and try again.")
        exit
    }
    write-verbose("Object ID for AAD group $ShareAdminGroupName is $elevatedContributorObjectId")
} else {
    write-warning "Group $ShareAdminGroupName not found in AD."
    exit 
}

if (get-AdGroup -Identity $ShareUserGroupName) {
    write-verbose ("Getting ObjectID for AAD group $ShareUserGroupName...")
    $filter = "Displayname eq '$ShareUserGroupName'"
    $ContributorObjectId = (Get-AzureADGroup -filter $filter).ObjectId
    if ($true -ne $?) {
        write-warning ( "Error retrieving information for group $ShareUserGroupName.  Check the name and try again.")
        exit
    }
    write-verbose("Object ID for AAD group $ShareUserGroupName is $ContributorObjectId")
} else {
    write-warning "Group $ShareUserGroupName not found in AD!"
    exit 
}

# Assign SMB Contributor role to users on the share and the elevated contributor role to admins
$scope = (Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRGName).Id + "/fileservices/default/fileshares/" + $profileShareName

write-verbose ("Assigning role `Storage File Data SMB Share Contributor to ObjectID $ContributorObjectID...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Contributor" -Scope $scope -ObjectId $ContributorObjectId

write-verbose ("Assigning role `Storage File Data SMB Share Elevated Contributor to ObjectID $elevatedContributorObjectID...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Elevated Contributor" -Scope $scope -ObjectId $elevatedContributorObjectId


################################
# Map Drive with storage Key / Set NTFS permissions on root
#################################

# below needed for setting NTFS rights on file system - can also do manually
$ShareName		= $profileShareName
$drive 			= "Y:"
$path = $drive + "\"
$Mapkey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountRGName -Name $storageAccountName).value[0]

################################
# Note that the next line is for Azure Commercial - must change DNS suffix for soverign clouds
#   Azure Gov:  .file.core.usgovcloudapi.net
################################
if ($isGovCloud) {
    $MapPath = "\\"+$storageAccountName+".file.core.usgovcloudapi.net\"+$ShareName
} else {
    $MapPath = "\\"+$storageAccountName+".file.core.windows.net\"+$ShareName
}

write-verbose ("Mounting the $profileShareName share...")
$result = new-smbmapping -LocalPath $drive -RemotePath $MapPath -UserName $storageAccountName -Password $Mapkey -Persistent $false

if (!($result.status -eq "OK")) {
    write-warning "Attempt to map path $MapPath failed."
    exit 
}

Write-verbose ("Successfully mounted $MapPath as drive $drive")

##############################################################
#  Let's list out the ACLs on the screen so we see what's there already
##############################################################
$acl = Get-Acl $path
# $acl.Access | where IsInherited -eq $false #Gets all non inherited rules.

# from https://blog.netwrix.com/2018/04/18/how-to-manage-file-system-acls-with-powershell-scripts/

##############################################################
# Modify existing entry for "Users"

write-verbose ("Setting Users (modify, this folder only)...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "Users", "Modify,Synchronize", "None", "None", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

# CREATOR OWNER / Subfolders and Files Only / Modify
write-verbose ("Setting CREATOR OWNER (modify, subfolders and files only)...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "CREATOR OWNER", "Modify,Synchronize", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path


##############################################################
#  Uncomment to list out the resulting ACL on the share.
##############################################################
# $acl = Get-Acl $path
# $acl.Access | where IsInherited -eq $false #Gets all non inherited rules.

Write-Verbose ("Disconnecting from file share...")
Remove-SmbMapping -LocalPath $drive -Force

Write-Verbose ("Execution complete.")