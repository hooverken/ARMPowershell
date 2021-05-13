# Configure-AzStorageAccountForADDSAuthN.ps1
# by Ken Hoover <ken dot hoover at micriosoft dotcom>

# This script configures an Azure storage account for authentication using ADDS Authentication
# 
# Based on work by John Kelbley <johnkel at Microsoft dotcom>

# April 2021

###############################################################################################################
#  This is the "Manual" process to configure AD authentication for Azure Files
#  (automated!)
#
#  Assumes:
#   * You are executing this script as a user with rights to create a computer account in the AD OU provided
#   * You are running this script from a system that is joined to the same AD that you want to use for authentication
#   * You have the "Az" module installed
#   * You have connected to Azure using Connect-AzAccount and used Select-AzSubscription to switch context to the
#     subscription where the storage account is located.
#	* You have AAD synced to AD (have you confirmed this is working?)
# 
# Process here:  https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable
#
###############################################################################################################
#
# CHANGELOG
# 13 MAY 2021 : Check for AD enabled status before doing anything and removed storageAccountRGName variable

#requires -runasAdministrator

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,      # The name of the storage account to configure
    [Parameter(mandatory = $true)][string]$ADOuDistinguishedName,   # The full DN of the OU to put the new computer object in
    [Parameter(mandatory = $false)][switch]$IsGovCloud              # MUST add this parameter if you're working in Azure Gov Cloud, otherwise don't use it
)

# Some sanity checks before we get started

# Make sure we are connected to Azure
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("You must connect to Azure with Connect-AzAccount before running this script.")
    exit
}

# Storage account name needs to be <= 15 characters to avoid risk of hitting legacy NetBIOS limits in AD
if ($storageAccountName.Length -ge 15) {
    write-warning ("Storage account name (" + $storageAccountName.Length + ") is over 15 characters.  Please use a shorter name to avoid issues.")
    exit
}

# Confirm that the storage account specified actually exists.
# This method is inefficient and can take several seconds but doing it this way means that we don't need to ask the user for the RG name.
# Since storage account names must be globally unique the chance of getting the "wrong" storage account from this is basically zero.
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName}

if ($null -ne $storageAccount) {
    # First make sure that this storage account is not already configured for ADDS.  If so, exit so we don't touch it.
    Write-verbose "Checking to see if this storage account is already configured for AD authentication..."
    if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
        ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
        write-warning ("Storage account $storageAccountName is already configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
        exit 
    } else {
        # The storage account is not configured for ADDS
        # Create a Kerb key for the storage account to use with ADDS
        write-verbose ("Creating Kerberos key for storage account $storageAccountName")
        New-AzStorageAccountKey -ResourceGroupName $storageaccount.ResourceGroupName -name $storageAccount.StorageAccountName -KeyName kerb1 | Out-Null
        $Keys = get-azstorageaccountkey -ResourceGroupName $storageaccount.ResourceGroupName -Name $storageAccount.StorageAccountName -listkerbkey
        $kerbkey = $keys | where-object {$_.keyname -eq 'kerb1'} 
        $CompPassword = $kerbkey.value | ConvertTo-Securestring -asplaintext -force
    }
} else {
    # we didn't find the specified storage account name in the current scope.
    Write-Warning ("Storage account $storageAccountName not found.")
    exit
}

#######################################################################
# Create Computer Account and SPN; get AD information

# AD Settings - These pull the info we need about the AD domain/forest:
$Forest = Get-ADForest
$Domain = get-ADdomain

if ((!($Forest)) -or (!($Domain))) {
    write-error ("Unable to contact to ADDS. Exiting.")
    exit
}

# For Azure Commercial
# SPN looks like    :		cifs/your-storage-account-name-here.file.core.windows.net	
# For Gov looks like:		cifs/your-storage-account-name-here.file.core.usgovcloudapi.net 

if ($isGovCloud)  {
	$SPN = "cifs/$storageAccountName.file.core.usgovcloudapi.net" 
} Else { 
	$SPN = "cifs/$storageAccountName.file.core.windows.net" 
}

Write-Verbose "SPN for new account will be $SPN"

if (Get-AzStorageAccount -Name $storageAccount.StorageAccountName -ResourceGroupName $storageAccount.ResourceGroupName) {

    # Make sure the target OU DN actually exists just to make sure
    $OUlist = get-adobject -filter 'ObjectClass -eq "organizationalUnit"'
    if ($oulist.distinguishedName -contains $ADOuDistinguishedName) {
        if (get-ADComputer -Filter { Name -eq '$storageAccountName' } -ErrorAction SilentlyContinue) {
            write-verbose ("Computer object $storageAccountName already exists in AD.")
        } else {
            write-verbose ("Creating computer object in AD...")
            $result = New-ADComputer -name $storageAccount.StorageAccountName -path $ADOUDistinguishedName `
                -Description "DO NOT DELETE - Azure File Share Authentication Account" `
                -ServicePrincipalNames $SPN `
                -PasswordNeverExpires $true `
                -OperatingSystem "Azure Files" `
                -AccountPassword $CompPassword
        }
    } else {
        write-warning ("OU `"$ADOuDistinguishedName`" not found.")
        exit
    }
} else {
    write-warning ("Storage account " + $storageAccount.StorageAccountName + " not found in RG " + $storageAccount.ResourceGroupName + ". Exiting")
}

$Computer = get-ADComputer $storageAccount.StorageAccountName  # The computer object in AD for the share.

# if you fail to create the account, it could be rights (often), but commonly the DN for the OU is wrong (folks guess at it!)
# check to see what the DN actually is either in ADUC or pull all the OUs with the following command:
# 	get-adobject -filter 'ObjectClass -eq "organizationalUnit"'

###################################################
#Step 3 update Storage account to use ADDS AuthN
###################################################
#
# Set the feature flag on the target storage account and provide the required AD domain information
write-verbose ("Configuring " + $storageaccount.StorageAccountName + " for ADDS Authentication...")
$updateresult = Set-AzStorageAccount `
        -ResourceGroupName $storageaccount.ResourceGroupName `
        -Name $storageaccount.StorageAccountName `
        -EnableActiveDirectoryDomainServicesForFile $true `
        -ActiveDirectoryDomainName $Domain.dnsroot `
        -ActiveDirectoryNetBiosDomainName $Domain.netbiosname `
        -ActiveDirectoryForestName $Forest.name `
	    -ActiveDirectoryDomainGuid $Domain.ObjectGUID `
        -ActiveDirectoryDomainsid $Domain.DomainSID `
        -ActiveDirectoryAzureStorageSid $Computer.sid

if (!($updateresult)) {
    write-warning "An error occurred while updating the storage account.  Exiting."
    exit 
}

#################################
# Confirm settings
#################################

Write-verbose ("Verifying...")
# Re-read the target storage account;s info and verify that it shows as AD enabled.
$storageaccount = Get-AzStorageAccount -ResourceGroupName $storageaccount.ResourceGroupName -Name $storageAccount.StorageAccountName

if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account " + $storageaccount.StorageAccountName + " is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("Storage account configuration does not match expectations.  Please check and try again.")
    exit 
}
