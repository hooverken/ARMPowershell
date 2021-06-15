#Requires -Modules "Az", "AzureADPreview"
#Requires -PSEdition Core

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
# 15 June 2021  - Added Requires directives

############################################################################
# Required parameters - make sure you have all of this info ahead of time
#

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,  # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$shareName,           # The name of the share.  The share will be created if it does not exist.
    [Parameter(mandatory = $true)][string]$AppAttachSessionHostManagedIdAADGroupName,  # The name of an AZURE AD group containing the managed identities of the VM's that will be using app attach
    [Parameter(mandatory = $true)][string]$AppAttachUsersADDSGroupName, # The name of an AD group containing users that can access attached apps
    [Parameter(mandatory = $true)][string]$AppAttachComputersADDSGroupName, # The name of an AD group containing the computer objects of the machines that need to use attached apps.  This group must be synchronized to AzureAD
    [Parameter(mandatory = $false)][switch]$IsGovCloud         # MUST add this parameter if you're working in Azure Gov Cloud, otherwise don't use it
)


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

# Confirm that the storage account specified actually exists
# Yes, this method is slow but it means that we don't need to ask the user for the resource group name of the storage account
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }

Write-Verbose ("Verifying that we can connect to the storage account")
if ($storageAccount) {
    # Grab the RG name that the storage account is in since we'll need it.
    $storageAccountRGName = $storageaccount.ResourceGroupName
} else {
    Write-Warning ("Storage account $storageAccountName not found in current subscription.")
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


#####################################################
# Set IAM Roles for the share

# Required permissions/iam roles for MSIX App Attach:
#
# The following items need the "Storage File SMB Data Reader" IAM Role
#
# * The managed identities of WVD session hosts (ref: https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-portal-windows-vm )
# * The AD users that need to use attached apps (users must be synced with onprem AD)
# * The AD computer objects of the systems that will be connecting to the share

## Set the IAM Roles on the file share

Write-verbose ("Setting storage context...")
$storageAccountKey = (get-AzStorageAccountKey -ResourceGroupName $storageAccountRGName -Name $storageAccountName)[0].Value
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

# Verify that the target share exists.  If not, create it.
Write-Verbose ("Checking if share $sharename exists in storage account $storageAccountName...")
if ($null -eq (get-AzStorageShare -Name $sharename -Context $storageContext -ErrorAction SilentlyContinue)) {
    write-verbose ("File share $sharename does not exist.  Creating new share $sharename...")
    New-AzStorageShare -Name $sharename -Context $storageContext
} else {
    write-verbose ("Share $sharename is present (OK)")
}


# Retrieve the object ID's for the AzureAD groups that need IAM roles assigned
Write-Verbose ("Retrieving AzureAD group information...")
$MSIXHostManagedIdentitiesGroup = Get-AzAdGroup -DisplayName $AppAttachSessionHostManagedIdAADGroupName -ErrorAction SilentlyContinue
$MSIXAppAttachAADUsersGroup     = Get-AzAdGroup -DisplayName $AppAttachUsersADDSGroupName -ErrorAction SilentlyContinue
$MSIXAppAttachADDSComputerGroup = Get-AzAdGroup -DisplayName $AppAttachComputersADDSGroupName -ErrorAction SilentlyContinue

if(-not ($MSIXHostManagedIdentitiesGroup -and $MSIXAppAttachAADUsersGroup -and $MSIXAppAttachADDSComputerGroup)) {
    write-warning ("Could not find group name $AppAttachComputersADDSGroupName, $AppAttachSessionHostManagedIdAADGroupName or $AppAttachUsersADDSGroupName.  Please verify names and try again.")
    exit
}

# Set the scope for the role assignment (just the share)
$scope = (Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRGName).Id + "/fileservices/default/fileshares/" + $shareName

# Grant the "Storage File Data SMB Share reader" roles to the three groups
write-verbose ("Assigning role Storage File Data SMB Share Reader to group `"" + $MSIXHostManagedIdentitiesGroup.DisplayName + "`"...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Reader" -Scope $scope -ObjectId $MSIXHostManagedIdentitiesGroup.Id

write-verbose ("Assigning role Storage File Data SMB Share Reader to group `"" + $MSIXAppAttachADDSComputerGroup.DisplayName + "`"...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Reader" -Scope $scope -ObjectId $MSIXAppAttachADDSComputerGroup.Id

write-verbose ("Assigning role Storage File Data SMB Share Reader to group `"" + $MSIXAppAttachAADUsersGroup.DisplayName + "`"...")
$result = New-AzRoleAssignment -RoleDefinitionName "Storage File Data SMB Share Reader" -Scope $scope -ObjectId $MSIXAppAttachAADUsersGroup.Id


# Update NTFS permissions so the AD objects can access the share

$ShareName  = $shareName
$drive      = "Y:"
$path       = $Drive + "\"

if ($isGovCloud) {
    $MapPath = "\\"+$storageAccountName+".file.core.usgovcloudapi.net\"+$sharename
} else {
    $MapPath = "\\"+$storageAccountName+".file.core.windows.net\"+$sharename
}

write-verbose ("Mounting $MapPath...")
$result = new-smbmapping -LocalPath $drive -RemotePath $MapPath -UserName $storageAccountName -Password $storageAccountKey -Persistent $false

if (!($result.status -eq "OK")) {
    write-warning "Attempt to mount $MapPath failed."
    exit 
}

Write-verbose ("Successfully mounted $MapPath as drive $drive")

write-verbose ("Adding `"Users`" to NTFS ACL on the file share (ReadAndExecute)...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList "Users", "ReadAndExecute", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

write-verbose ("Adding `"$AppAttachComputersADDSGroupName`" to NTFS ACL on the file share (ReadAndExecute)...")
$acl = Get-Acl $path
$rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $AppAttachComputersADDSGroupName, "ReadAndExecute", "ContainerInherit, ObjectInherit", "InheritOnly", "Allow"
$acl.SetAccessRule($rule)
$result = $acl | Set-Acl -Path $path

Write-Verbose ("Removing drive mapping...")
Remove-SmbMapping -LocalPath $drive -Force

Write-Verbose ("Execution complete.")
