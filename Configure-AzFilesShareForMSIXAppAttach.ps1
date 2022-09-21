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

############################################################################
# Required parameters - make sure you have all of this info ahead of time
#

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,  # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$shareName,           # The name of the share.  The share will be created if it does not exist.
#    [Parameter(mandatory = $true)][string]$AppAttachSessionHostManagedIdAADGroupName,  # The name of an AD group containing the computer objects of the machines that need to use attached apps.  This group must be synchronized to AzureAD
    [Parameter (Mandatory = $False, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)][string]$appAttachADUsersGroup = "Domain Users",
    [Parameter (Mandatory = $False, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)][string]$appAttachADComputersGroup = "Domain Computers"
    )

# If the AD groups for users and/or computers are not specified then "Domain Users" and "Domain Computers" will be used

##################################################################################


# The following things must all be true for MSIX App Attach to work correctly:

# - The VM's in the host pool must have system-managed identities enabled
# - There must be a group in AAD containing the managed identities
# - The target storage account must be configured for ADDS Authentication
# 


# Some sanity checks before we get started

# Make sure we are connected to Azure
Write-Verbose ("Verifying that we are connected to Azure...")
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("You must connect to Azure with Connect-AzAccount before running this script.")
    exit
}

# Share names for Azure Files must be all lowercase so force whatever the user entered to lowercase.
# ref: https://docs.microsoft.com/en-us/rest/api/storageservices/Naming-and-Referencing-Shares--Directories--Files--and-Metadata
$sharename = $sharename.ToLower()

# Confirm that the storage account specified actually exists and that we can connect to it.
# Yes, this method is slow but it means that we don't need to ask the user for the resource group name of the storage account
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


# Check that the specified file share exists.  If it doesn't then create it.
Write-verbose ("Setting storage context...")
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
Write-Verbose ("Checking if share $sharename exists in storage account $storageAccountName...")
if ($null -eq (get-AzStorageShare -Name $sharename -Context $storageContext -ErrorAction SilentlyContinue)) {
    write-verbose ("File share $sharename does not exist.  Creating new share $sharename...")
    New-AzStorageShare -Name $sharename -Context $storageContext
} else {
    write-verbose ("Share $sharename is present (OK)")
}

###############################################################################################
# Set default file share permission for this storage account to StorageFileDataSmbShareReader
# This avoids having to do individual IAM role assignments which makes this script a lot simpler than it used to be

$defaultPermission = "StorageFileDataSmbShareReader" # Default permission (IAM Role) for the share
write-verbose ("Setting default File share permissions for "+ $storageaccount.storageAccountName + "to $defaultPermission")
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
$unusedDriveLetters = [Char[]](90..65) | Where-Object { (Test-Path "${_}:\") -eq $false }
$driveLetter = $unusedDriveLetters[0] + ":"  # using the first one

$MapPath = "\\$endpointfqdn\"+$sharename  # The complete UNC path to the share

# Get the storage account key 
Write-Verbose ("Getting storage account key for $storageAccountName...")
$storageAccountKey = (get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName)[0].Value
if ($null -eq $storageAccountKey) { 
    write-warning ("Unable to retrieve storage account key for $storageAccountName")
    exit 
}

write-verbose ("Mounting $MapPath...")
$result = new-smbmapping -LocalPath $driveLetter -RemotePath $MapPath -UserName $storageAccountName -Password $storageAccountKey -Persistent $false

if (!($result.status -eq "OK")) {
    write-warning "Attempt to mount $MapPath failed."
    exit 
}

Write-verbose ("Successfully mounted $MapPath as drive $drive")

write-verbose ("Adding `"$appAttachADUsersGroup`" to NTFS ACL on the file share (ReadAndExecute)...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $appAttachADUsersGroup, "ReadAndExecute", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

write-verbose ("Adding `"$appAttachADComputersGroup`" to NTFS ACL on the file share (ReadAndExecute)...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $appAttachADComputersGroup, "ReadAndExecute", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

Write-Verbose ("Removing drive mapping...")
Remove-SmbMapping -LocalPath $driveLetter -Force

Write-Verbose ("Execution complete.")