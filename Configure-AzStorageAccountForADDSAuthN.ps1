# Configure-AzStorageAccountForADDSAuthN.ps1
# by Ken Hoover <ken dot hoover at Microsoft dotcom>

# This script configures an Azure storage account for authentication using ADDS Authentication
# 
# Based on work by John Kelbley <johnkel at Microsoft dotcom>

# initial release April 2021
# last update Sept 2022

###############################################################################################################
#  This is the "Manual" process to configure AD authentication for Azure Files
#  (automated!)
#
#  Assumes:
#   * You are executing this script as a user with rights to create a computer account in the AD OU provided
#   * You are running this script from a system that is joined to the same AD that you want to use for authentication
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
# 21 Sep 2022 : Powershell 7 now required
#               storage account length constraint enforced by parameter validation
#               Reduced number of modules required to function (Az.Accounts, Az.Resources, Az.Storage)
#               Auto-install of missing modules
#               Installs RSAT tools if not present (needed for ActiveDirectory module)
#               Simplified logic in a few places.

<#
.SYNOPSIS

This script configures an Azure storage account for authentication using ADDS Authentication.

.DESCRIPTION

This script configures an Azure storage account for authentication using ADDS Authentication  
    
To use it, follow these steps:

1. Log into a workstation which is joined to the same AD domain that you want the storage account to use for authentication using an AD user with permission to add a computer object to the desired OU

2. Connect to Azure using Connect-AzAccount and use Select-AzSubscription to switch context to the subscription where the storage account is located.

3. Run this script, providing the storage account name and the DN of the OU to create the new computer object in as parameters.

.PARAMETER storageAccountName

The name of the storage account to configure.  The storage account must exist and have a name which is 15 characters or less in length to avoid legacy NetBIOS naming issues.

.PARAMETER ADOUDistinguishedName

The full distinguished name (DN) of the OU in AD where the computer account will be created, such as "OU=MyOU,DC=MyDomain,DC=local"

.PARAMETER IsGovCloud

Indicates whether the storage account to modify is in a US Government Azure environment

.EXAMPLE

    .\Configure-AzStorageAccountForADDSAuthN.ps1 -storageAccountName "myStorageAccount" -ADOUDistinguishedName "OU=MyOU,DC=MyDomain,DC=local"

.EXAMPLE

    .\Configure-AzStorageAccountForADDSAuthN.ps1 -storageAccountName "myStorageAccount" -ADOUDistinguishedName "OU=MyOU,DC=MyDomain,DC=local" -IsGovCloud

.LINK
    https://www.github.com/hooverken/ARM-Powershell
#>

#requires -runasAdministrator
#requires -version 7.0

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][ValidateLength(1,15)][string]$storageAccountName,     # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$ADOuDistinguishedName,   # The full DN of the OU to put the new computer object in
    [Parameter(mandatory = $false)][switch]$IsGovCloud              # MUST add this parameter if you're working in Azure Gov Cloud, otherwise don't use it
)


# Check as many of the prerequisites as we can before we do anything.

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

# Confirm that the storage account specified actually exists.
# This method is inefficient and can take several seconds but doing it this way means that we don't need to ask 
# the user for the RG name.
# Since storage account names must be globally unique the chance of getting the "wrong" storage account from this is basically zero.
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName}

if ($null -ne $storageAccount) {
    # First make sure that this storage account is not already configured for ADDS.  If so, exit so we don't touch it.
    Write-verbose "Checking to see if this $storageAccountName is already configured for AD authentication..."
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

# Verify that we can connect to the storage account's file service on port 445.
if (Test-NetConnection -ComputerName "$storageAccountName.file.core.windows.net" -Port 445 -InformationLevel Quiet) {
    Write-Verbose ("Connectivity to $storageAccountName.file.core.windows.net on port 445/TCP confirmed.")
} else {
    Write-Warning ("Unable to connect to $storageAccountName.file.core.windows.net on port 445.  Please verify that the storage account exists and that the file service is enabled.")
    exit
}


#######################################################################
# Create Computer Account and SPN; get AD information

# AD Settings - These pull the info we need about the AD domain
$currentDomain = (get-computerinfo).csdomain  # the domain that this computer is joined to
$Domain = get-ADdomain -Identity $currentDomain  # get domain info directly from a DC

if (-not $Domain) {  # Can't talk to a domain controller
    write-error ("Unable to connect to a DC for `"$currentDomain`". Exiting.")
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

# Make sure the target OU DN exists just to make sure
$domainName = $domain.dnsroot
$OUlist = get-adobject -filter 'ObjectClass -eq "organizationalUnit"'
if ($oulist.distinguishedName -contains $ADOuDistinguishedName) {
    if (get-ADComputer -Filter { Name -eq $storageAccountName } -ErrorAction SilentlyContinue) {
        write-verbose ("Computer object $storageAccountName is present in $domainName")
    } else {
        write-verbose ("Creating computer object in domain $domainName for $storageAccountName")
        $result = New-ADComputer $storageAccount.StorageAccountName `
            -path $ADOUDistinguishedName `
            -Description "DO NOT DELETE - Azure File Share Authentication Account" `
            -ServicePrincipalNames $SPN `
            -PasswordNeverExpires $true `
            -OperatingSystem "Azure Files" `
            -AccountPassword $CompPassword
        if (-not (get-ADComputer -Filter { Name -eq $storageAccountName } -ErrorAction SilentlyContinue)) {
            $result
            write-error ("Unable to create computer object for $storageAccountName in AD.")
            exit
        }
    }
} else {
    write-warning ("OU `"$ADOuDistinguishedName`" not found.  Please verify that the OU exists and try again.")
    exit
}


#######################################################
# Step 3 Configure Azure storage account to use ADDS AuthN
#######################################################
#
# Set the feature flag on the target storage account and provide the required AD domain information
write-verbose ("Configuring " + $storageaccount.StorageAccountName + " for ADDS Authentication...")

$Computer = get-ADComputer $storageAccount.StorageAccountName  # The computer object in AD for this storage account

$updateresult = Set-AzStorageAccount `
        -ResourceGroupName $storageaccount.ResourceGroupName `
        -Name $storageaccount.StorageAccountName `
        -EnableActiveDirectoryDomainServicesForFile $true `
        -ActiveDirectoryDomainName $Domain.dnsroot `
        -ActiveDirectoryNetBiosDomainName $Domain.netbiosname `
        -ActiveDirectoryForestName $Domain.Forest `
	    -ActiveDirectoryDomainGuid $Domain.ObjectGUID `
        -ActiveDirectoryDomainsid $Domain.DomainSID `
        -ActiveDirectoryAzureStorageSid $Computer.sid

if (!($updateresult)) {
    write-warning "An error occurred while updating the storage account.  Exiting."
    $updateresult
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
