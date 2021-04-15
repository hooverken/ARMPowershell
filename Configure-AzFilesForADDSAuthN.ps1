# Configure-AzFilesForADDSAuthN.ps1

# This script configures an Azure Files share for authentication using ADDS Authentication
# 
# Based on work by version by John Kelbley <johnkel at Microsoft dotcom>
# Scriptified/Parameterized by Ken Hoover <ken dot hoover at Microsoft dotcom>

# February 2021

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
#
# 11 Jan 2021 : Find storageAccountRGName for ourselves instead of forcing the user to provide it.
# 24 Feb 2021 : Modified original script to only do the ADDS stuff by cutting out everything after section 3
#               and removing the now-unnecessary paramters and dependencies.
#
#
############################################################################
# Required parameters - make sure you have all of this info ahead of time
############################################################################
#
[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,      # The name of the storage account with the share
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

# Storage account name needs to be < 15 characters to avoid risk of hitting legacy NetBIOS limits in AD
if ($storageAccountName.Length -ge 15) {
    write-warning ("Storage account name (" + $storageAccountName.Length + ") is over 15 characters.  Please use a shorter name to avoid issues.")
    exit
}

# Confirm that the storage account specified actually exists and populate storageAccountRGName
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName}
    
if ($storageAccount) {
    $storageAccountRGName = $storageaccount.ResourceGroupName
    # Create a Kerb key for the storage account to use with ADDS
    write-verbose ("Creating Kerberos key for storage account $storageAccountName")
    New-AzStorageAccountKey -ResourceGroupName $storageAccountRGName -name $storageAccountName -KeyName kerb1 | Out-Null
    $Keys = get-azstorageaccountkey -ResourceGroupName $storageAccountRGName -Name $storageAccountName -listkerbkey
    $kerbkey = $keys | where-object {$_.keyname -eq 'kerb1'} 
    $CompPassword = $kerbkey.value | ConvertTo-Securestring -asplaintext -force
} else {
    Write-Warning ("Storage account $storageAccountName not found.")
    exit
}

#######################################################################
#Step 2 Create Computer Account and SPN, and get AD information
#######################################################################

# AD Settings - These pull the info we need about the AD domain/forest:
$Forest = Get-ADForest
$Domain = get-ADdomain

if ((!($Forest)) -or (!($Domain))) {
    write-error ("Unable to contact to ADDS. Exiting.")
    exit
}

# For Azure Commercial
# SPN should look like:		cifs/your-storage-account-name-here.file.core.windows.net	
# For Gov looks like:		cifs/your-storage-account-name-here.file.core.usgovcloudapi.net 
#
if ($isGovCloud)  {
	$SPN = "cifs/$storageAccountName.file.core.usgovcloudapi.net" 
} Else { 
	$SPN = "cifs/$storageAccountName.file.core.windows.net" 
}

Write-Verbose "SPN for new account will be $SPN"

if (Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRGName) {

    # Make sure the target OU DN actually exists just to make sure
    $OUlist = get-adobject -filter 'ObjectClass -eq "organizationalUnit"'
    if ($oulist.distinguishedName -contains $ADOuDistinguishedName) {
        if (get-ADComputer -Filter { Name -eq '$storageAccountName' } -ErrorAction SilentlyContinue) {
            write-verbose ("Computer object $computeraccountName already exists in AD.")
        } else {
            write-verbose ("Creating computer object in AD...")
            $result = New-ADComputer -name $storageAccountName -path $ADOUDistinguishedName `
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
    write-warning ("Storage account $storageAccountName not found in RG $storageAccountRGName. Exiting")
}

$Computer = get-ADComputer $storageAccountName  # The computer object in AD for the share.

# if you fail to create the account, it could be rights (often), but commonly the DN for the OU is wrong (folks guess at it!)
# check to see what the DN actually is either in ADUC or pull all the OUs with the following command:
# 	get-adobject -filter 'ObjectClass -eq "organizationalUnit"'

###################################################
#Step 3 update Storage account to use ADDS AuthN
###################################################
#
# Set the feature flag on the target storage account and provide the required AD domain information
write-verbose ("Configuring storage account $storageAccountName for ADDS Authentication...")
$updateresult = Set-AzStorageAccount `
        -ResourceGroupName $storageAccountRGName `
        -Name $storageAccountName `
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
#Step 4 Confirm settings
#################################

# Get the target storage account
$storageaccount = Get-AzStorageAccount -ResourceGroupName $storageAccountRGName -Name $storageAccountName

if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account $storageAccountName is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("Storage account configuration does not match expectations.  Please check and try again.")
    exit 
}
