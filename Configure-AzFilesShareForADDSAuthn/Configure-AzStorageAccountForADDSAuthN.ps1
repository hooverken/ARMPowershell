# Configure-AzStorageAccountForADDSAuthN.ps1
# by Ken Hoover <ken dot hoover at Microsoft dotcom>

# This script configures an Azure storage account for authentication using ADDS Authentication
# 
# Based on work by John Kelbley <johnkel at Microsoft dotcom>

# initial release April 2021
# last update Oct 2022

###############################################################################################################
#  This is the "Manual" process to configure AD authentication for Azure Files, automated!
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
# 13 May 2021 : Check for AD enabled status before doing anything and removed storageAccountRGName variable
# 21 Sep 2022 : Powershell 7 now required
#               storage account length constraint enforced by parameter validation
#               Reduced number of modules required to function (Az.Accounts, Az.Resources, Az.Storage)
#               Auto-install of missing modules
#               Installs RSAT tools if not present (needed for ActiveDirectory module)
#               Simplified logic in a few places.
#               Removed isGovCloud parameter since we can set the SPN using attributes of the storage account
# 29 Sep 2022 : Adapted SPN logic to work with any cloud environment (not just AzureCloud)
# 30 Sep 2022 : Add support for cases where the computer object already exists in the target OU (Issue #7)
#               Require user to provide a credential (and domain name) to talk to AD rather than assuming 
#                 that we're running as a user with access to do the AD work
# 18 Oct 2022 : Prompt for connection to Azure if Get-AzContext fails so we don't confuse the user
#                 by making them re-run the script, especially if the necessary PS modules had to be
#                 installed.

<#
.SYNOPSIS

This script configures an Azure storage account for authentication using ADDS Authentication.

.DESCRIPTION

This script configures an Azure storage account for authentication using ADDS Authentication  
    
See https://github.com/hooverken/ARMPowershell/tree/main/Configure-AzFilesShareForADDSAuthn for information on how it works, prerequisites and usage information.

.PARAMETER storageAccountName

The name of the storage account to configure.  The storage account must exist and have a name which is 15 characters or less in length to avoid legacy NetBIOS naming issues.

.PARAMETER ADDomainFQDN

The fully qualified domain name of the AD domain to use for authentication.

.PARAMETER ADOUDistinguishedName

The full distinguished name (DN) of the OU in AD where the computer account will be created, such as "OU=MyOU,DC=MyDomain,DC=local"

.PARAMETER Credential

A PSCredential object for a user with rights to add/update the computer account in the OU specified by ADOUDistinguishedName.  This user must be able to add a computer account to the OU specified by ADOUDistinguishedName.

.EXAMPLE

    .\Configure-AzStorageAccountForADDSAuthN.ps1 -storageAccountName "myStorageAccount" -ADDomainFQDN ad.contoso.com -ADOUDistinguishedName "OU=MyOU,DC=ad,DC=contoso,DC=com" -Credential $cred

.LINK
    https://github.com/hooverken/ARMPowershell/tree/main/Configure-AzFilesShareForADDSAuthn
#>

#requires -version 7.0

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][ValidateLength(1,15)][string]$storageAccountName,     # The name of the storage account with the share
    [Parameter(mandatory = $true)][string]$ADDomainFQDN,   # The full name of the domain to join like "ad.contoso.us"
    [Parameter(mandatory = $true)][string]$ADOuDistinguishedName,   # The full DN of the OU to put the new computer object in
    [Parameter(mandatory = $true)][pscredential]$Credential   # PSCredential for a user with privilege to create/update a computer object in the target OU
)

########################################################################################

# Check as many of the prerequisites as we can before we do anything.

# Verify that the required Powershell modules are installed.  If not, install them.

Write-Verbose ("Verifying that the necessary Azure Powershell modules are present.")
$requiredModules = @("Az.Accounts", "Az.Storage", "Az.Resources")
$requiredModules | ForEach-Object {
    if (-not (Get-Module -Name $_ -ListAvailable)) {
        Write-Verbose ("Module $_ is not installed.  Installing it now.")
        Install-Module -Name $_ -Force -Scope CurrentUser
    } else {
        write-verbose ("Module $_ is present.")
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
        write-verbose "Module ActiveDirectory is present."
    }
}

# Make sure we are connected to Azure
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("Not connected to Azure (no context)`nPlease connect to Azure with Connect-AzAccount.")
    if (Get-Command -Module Az.Accounts Connect-AzAccount) {
        Connect-AzAccount
    } else {
        Write-Error "The Az.Accounts module is not installed.  Please install it and try again."
        exit 
    }
}

# Verify that the AD credential we were given is valid
if (-not ($Domain = Get-ADDomain -Identity $ADDomainFQDN -Credential $Credential)) {
    write-warning ("The AD credential provided is not valid for domain $ADDomainFQDN.")
    exit
} else {
    write-verbose ("The AD credential provided is valid for domain $ADDomainFQDN.")
}

# Confirm that the storage account specified actually exists.
# This method is inefficient and can take several seconds but doing it this way means that we don't need to ask 
# the user for the RG name.
# Since storage account names must be globally unique the chance of getting the "wrong" storage account from this is basically zero.
write-verbose ("Verifying that $storageAccountName exists.  This may take a moment." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName}

if ($null -ne $storageAccount) {
    # First make sure that this storage account is not already configured for ADDS.  If so, exit so we don't touch it.
    Write-verbose "Checking to see if $storageAccountName is already configured for AD authentication..."
    if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
        ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
        Write-Output ("Storage account $storageAccountName is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
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
    Write-Warning ("Storage account $storageAccountName not found.  Are you looking in the correct subscription?")
    exit
}

# Verify that we can connect to the storage account's file service on port 445.

$result = ($storageaccount.PrimaryEndpoints.file -match "//(.*)/")
$fileEndpoint = $matches[1]

if (Test-NetConnection -ComputerName $fileEndpoint -Port 445 -InformationLevel Quiet) {
    Write-Verbose ("Connectivity to $fileEndpoint on port 445/TCP confirmed.")
} else {
    Write-Warning ("Unable to connect to $fileEndpoint on port 445.  Please verify that the file service is enabled.")
    exit
}


#######################################################################
# Create Computer Account and SPN; get AD information

# We should have pulled the domain info when we did the credential check above.

$SPN = "cifs/$fileEndpoint"  # the SPN we will create for the computer account.  This should work everywhere (including gov cloud)
Write-Verbose ("Active Directory SPN for this storage account will be set to $SPN")

# Make sure the target OU DN exists
$domainName = $Domain.dnsroot
$OUlist = Get-ADObject -filter 'ObjectClass -eq "organizationalUnit"' -Credential $Credential
if ($OUlist.distinguishedName -contains $ADOuDistinguishedName) {
    if (get-ADComputer -Filter { Name -eq $storageAccountName } -Credential $Credential -ErrorAction SilentlyContinue) {
        write-verbose ("Computer object $storageAccountName is present in $domainName")

        # Since the computer account already exists, update it
        write-verbose ("Updating password for computer object in domain $domainName for $storageAccountName")
        $result = Set-ADAccountPassword -Identity ("CN=$storageAccountName" + "," + $ADOuDistinguishedName) `
                     -Reset `
                     -NewPassword ($CompPassword | ConvertTo-SecureString -AsPlainText -Force) `
                     -Credential $Credential `
                     -Confirm:$false `
                     -ErrorAction Stop
        Write-Verbose ("Updating existing computer object $storageAccountName in domain $domainName.")
        $result = Set-ADComputer -Identity ("CN=$storageAccountName,$ADOuDistinguishedName") `
            -Description "DO NOT DELETE - Azure File Share Authentication Account" `
            -ServicePrincipalNames @{Add=$SPN} `
            -PasswordNeverExpires $true `
            -OperatingSystem "Azure Files" `
            -Credential $Credential `
            -ErrorAction Stop
    } else {
        # Computer account doesn't exist so create it
        write-verbose ("Creating computer object in domain $domainName for $storageAccountName")
        $result = New-ADComputer $storageAccount.StorageAccountName `
            -path $ADOUDistinguishedName `
            -Description "DO NOT DELETE - Azure File Share Authentication Account" `
            -ServicePrincipalNames $SPN `
            -PasswordNeverExpires $true `
            -OperatingSystem "Azure Files" `
            -AccountPassword $CompPassword `
            -Credential $Credential
        if (-not (get-ADComputer -Filter { Name -eq $storageAccountName } -Credential $Credential -ErrorAction SilentlyContinue)) {
            $result
            write-error ("Unable to create computer object $storageAccountName in OU `"$ADOuDistinguishedName`".")
            exit
        }
    }
} else {
    write-warning ("OU `"$ADOuDistinguishedName`" not found in $domainName.  Please verify that the OU exists and try again.")
    exit
}

#############################################################
# Step 3 Configure Azure storage account to use ADDS AuthN

#
# Set the feature flag on the target storage account and provide the required AD domain information
write-verbose ("Configuring " + $storageaccount.StorageAccountName + " for ADDS Authentication...")

$Computer = Get-ADComputer $storageAccount.StorageAccountName -Credential $Credential  # The computer object in AD for this storage account

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

Write-verbose ("Verifying.")
# Re-read the target storage account;s info and verify that it shows as AD enabled.
$storageaccount = Get-AzStorageAccount -ResourceGroupName $storageaccount.ResourceGroupName -Name $storageAccount.StorageAccountName

if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
    ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
    write-verbose ("Storage account " + $storageaccount.StorageAccountName + " is configured to use domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
} else {
    write-warning ("Storage account configuration does not match expectations.  Please check and try again.")
    exit 
}
Write-Verbose("Execution Complete.")
