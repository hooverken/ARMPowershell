# Configure-AzFilesShareForMSIXAppAttach.ps1
# by Ken Hoover <ken dot hoover at Microsoft dotcom>

# Configures an Azure Files share's NTFS permissions and IAM role assignments for use with
# MSIX App Attach (https://docs.microsoft.com/en-us/azure/virtual-desktop/app-attach-azure-portal)

# Based partly on work by John Kelbley <johnkel at Microsoft dotcom>

###############################################################################################################
#
#  Assumes:
#   * You have the "Az" and "AzureADPreview" modules installed
#   * You are connected via Connect-AzAccount as a user with sufficient IAM roles to manage the storage account
#   * You have connected to the target AzureAD environment using Connect-AzureAD
#	* You have AAD synced to AD (have you confirmed this is working?)
#   * The storage account is configured for ADDS authentication
#
###############################################################################################################
#
# CHANGELOG
#
# 15 April 2021 - Initial version derived from Configure-AzFilesForADDSandFSLogix.ps1
# 19 May 2021   - Added check that shared-key access is enabled (if it's disabled it breaks the NFTS permissions code)
# 14 Jul 2021   - Set default share permission for storage account to read-only instead of using IAM role assignments
#                 (ref: https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-assign-permissions)
# 04 Oct 2022   - Revamp to align with sister scripts to have fewer depenmdencies and add better prereq checks so that more runs are successful on the first try.
#                 Improved (and more precise) ACL-setting logic
#                 Improved drive-mapping logic

############################################################################
# Required parameters - make sure you have all of this info ahead of time
#

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,  # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$shareName,           # The name of the share.  The share will be created if it does not exist.
    [Parameter (Mandatory = $true)][string]$appAttachADUsersGroup,
    [Parameter (Mandatory = $true)][string]$appAttachADComputersGroup,
    [Parameter (Mandatory = $true)][PSCredential]$ADCredential  # Credentials of a user that can read AD group info (doesn't need admin)
)   

##################################################################################



# Verify that the required Powershell modules are installed.  If not, install them.

Write-Verbose ("Verifying that the necessary Azure Powershell modules are present.")
$requiredModules = @("Az.Accounts", "Az.Storage", "Az.Resources")
$requiredModules | ForEach-Object {
    if (-not (Get-Module -Name $_ -ListAvailable)) {
        Write-Verbose ("Module $_ is not installed.  Installing it now.")
        Install-Module -Name $_ -Force -Scope CurrentUser
    }
}


# The ActiveDirectory Module
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Host "The ActiveDirectory module is not installed.  Installing with DISM.  This may take a few minutes."
    $result = DISM.exe /Online /Get-Capabilities | select-string "Rsat.Active"

    # The ActiveDirectory RSAT package has a dependency on the ServerManager package so we might need to install 
    # ServerManager first.
    
    $ServerManagerCapability = "Rsat.ServerManager.Tools~~~~0.0.1.0"
    $ActiveDirectoryRSatModuleCapability = "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"

    if (-not (($result.toString().contains($ServerManagerCapability)) -and ($result.toString().contains($ActiveDirectoryRSatModuleCapability)))) {
        Write-warning("The ActiveDirectory Powershell module is not present.")
        $result = DISM.exe /Online /Get-CapabilityInfo /CapabilityName:$ServerManagerCapability
        if ($result.contains("State : Installed")) {
            Write-Host "Installing ActiveDirectory RSAT tools with DISM."
            DISM.exe /Online /Add-Capability /CapabilityName:$ActiveDirectoryRSatModuleCapability /NoRestart
        } else {
            Write-Host "Installing ServerManager and ActiveDirectory RSAT tools with DISM."
            DISM.exe /Online /Add-Capability /CapabilityName:$ServerManagerCapability /NoRestart
            DISM.exe /Online /Add-Capability /CapabilityName:$ActiveDirectoryRSatModuleCapability /NoRestart
        }
    } else {
        write-verbose "ActiveDirectory module is present."
    }
}

# Make sure we are connected to Azure
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("Please connect to Azure with Connect-AzAccount before running this script.")
    exit
}


# Share names for Azure Files must be all lowercase so force whatever the user entered to lowercase.
# ref: https://docs.microsoft.com/en-us/rest/api/storageservices/Naming-and-Referencing-Shares--Directories--Files--and-Metadata
$sharename = $sharename.ToLower()

# Confirm that the storage account specified actually exists and that we can connect to it.
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


# Verify that the storage account does not have shared key AuthN disabled.
# Ref: https://docs.microsoft.com/en-us/azure/storage/common/shared-key-authorization-prevent?tabs=portal
if ($false -eq $storageaccount.AllowSharedKeyAccess) {
    Write-Warning "Storage account " + $storageAccount.StorageAccountName + " is configured to prevent shared key access."
    Write-Warning "Please enable shared key access to this account before running this script."
    exit 
}

# Verify that the storage account is configured for ADDS AuthN
if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account $storageAccountName is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("$storageAccountName is not configured for ADDS Authentication.")
    exit 
}

# The AD group containing users that will nbe using MSIX-app-attached app;lications
if (-not ($appAttachADUsersGroupObj = Get-ADGroup $appAttachADUsersGroup -Server kentoso.us -Credential $ADCredential)) {
    Write-Warning ("Group `"$AppAttachADUsersGroup`" not found in AD.  This group must exist before running this script.")
    exit
} else {
    Write-Verbose ("Group `"$AppAttachADUsersGroup`" found in AD.")
}

# The AD group containing the computer objects for the AVD session hosts that will use MISX app attach
if (-not ($appAttachADComputersGroupObj= Get-ADGroup $appAttachADComputersGroup -server kentoso.us -Credential $ADCredential)) {
    Write-Warning ("Group `"$appAttachADComputersGroup`" not found in AD.  This group must exist before running this script.")
    exit
} else {
    Write-Verbose ("Group `"$appAttachADComputersGroup`" found in AD.")
}

# Check that the specified file share exists.  If it doesn't then create it.
Write-verbose ("Setting storage context.")
$storageContext = New-AzStorageContext -StorageAccountName $storageaccount.StorageAccountName `
                        -StorageAccountKey (get-AzStorageAccountKey `
                        -ResourceGroupName $storageAccount.resourcegroupname `
                        -Name $storageAccount.StorageAccountName)[0].Value
Write-Verbose ("Checking if share $sharename exists in storage account $storageAccountName...")
if ($null -eq (get-AzStorageShare -Name $sharename -Context $storageContext -ErrorAction SilentlyContinue)) {
    write-verbose ("File share `"$sharename`" does not exist.  Creating...")
    New-AzStorageShare -Name $sharename -Context $storageContext
} else {
    write-verbose ("Share `"$sharename`" is present on storage account `"$storageAccountName`".")
}

###############################################################################################
# Set default file share permission for this storage account to StorageFileDataSmbShareReader
# This avoids having to do individual IAM role assignments which makes this script a lot simpler than it used to be

$defaultPermission = "StorageFileDataSmbShareContributor" # Default permission (IAM Role) for the share
write-verbose ("Setting default File share permission for "+ $storageaccount.storageAccountName + "to $defaultPermission")
$storageAccount = Set-AzStorageAccount -ResourceGroupName $storageAccount.ResourceGroupName `
                                       -AccountName $storageAccount.StorageAccountName `
                                       -DefaultSharePermission $defaultPermission

# Verify that the change stuck
if (!($storageAccount.AzureFilesIdentityBasedAuth.DefaultSharePermission -eq $defaultPermission)) { 
    Write-Error ("Change to default permissions for storage account failed!")
    exit
} else { 
    Write-verbose ("Confirmed that default permissions are set correctly for " + $storageaccount.storageAccountName)
}


# Update NTFS permissions so the AD objects can access the share
Write-Verbose ("Setting NTFS permissions for share $shareName...")

# Find an unused drive letter to map to the file share
$unusedDriveLetters = [Char[]](90..65) | Where-Object { -not (((Get-SmbMapping).LocalPath -eq  "${_}:" ) -or (Test-Path "${_}:\")) }
$driveLetter = $unusedDriveLetters[0] + ":"  # using the first one

# Check if we already have a connection open to the same destination (even if it's a different share).  
# If so, drop the connection.
Get-SmbMapping | ForEach-Object {
    Write-Verbose ("Checking if there are any existing drive mappings to the same endpoint.")
    if ($_.RemotePath.contains($endpointFqdn)) {
        Write-Verbose ("Disconnecting existing SMB mount to "+ $_.RemotePath)
        Remove-SmbMapping -RemotePath $_.RemotePath -Force
    }
}

$MapPath = "\\$endpointFqdn\"+$sharename  # The complete UNC path to the share

# Get the storage account key 
Write-Verbose ("Getting storage account key for $storageAccountName...")
$storageAccountKey = (get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName)[0].Value
if ($null -eq $storageAccountKey) { 
    write-warning ("Unable to retrieve storage account key for $storageAccountName")
    exit 
}



write-verbose ("Mounting $MapPath...")
$result = New-SmbMapping -LocalPath $driveLetter -RemotePath $MapPath -UserName $storageAccountName -Password $storageAccountKey -Persistent $false

if (!($result.status -eq "OK")) {
    write-warning "Attempt to mount $MapPath failed."
    exit 
}

Write-verbose ("Successfully mounted $MapPath as drive $driveLetter")

Write-Verbose ("Updating ACL for $driveLetter...")

$acl = Get-Acl $driveletter

# remove write perms for Authenticated Users
# This works by taking the well-known SID for this special group and back-translating it to an identity object 
# which we can use to strip its reference from the ACL.
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

# Add the AAD group for elevated users
write-verbose ("... Adding `"$appAttachADUsersGroup`" (ReadAndExecute)")
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $appAttachADUsersGroupObj.SID, "ReadAndExecute", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
Group$acl.SetAccessRule($rule)

# Add the AAD group for normal users
write-verbose ("... Adding `"$appAttachADComputersGroup`" (ReadAndExecute)")
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $appAttachADComputersGroupObj.SID, "ReadAndExecute", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)

# Apply the new ACL
Write-Verbose ("Applying new ACL to $driveLetter...")
$acl | Set-Acl -Path $driveLetter

# Dismount the drive
Write-Verbose ("Removing drive mapping...")
Remove-SmbMapping -LocalPath $driveLetter -Force

Write-Verbose ("Execution complete.")