# Configure-AzStorageAccountForADDSAuthN.ps1
# by Ken Hoover <ken dot hoover at Microsoft dotcom>

# This script configures an Azure storage account for authentication using ADDS Authentication
# 
# Based on work by John Kelbley <johnkel at Microsoft dotcom>

# initial release April 2021
# last update March 2024

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
#               Storage account length constraint enforced by parameter validation
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
# 26 Jan 2023 : [BUG] Add explicit connect to AD domain controller based on a lookup for AD Web Services
# 22 Mar 2024 : Add check to see if running on a server or workstation before installing prerequisites.  This
#               is needed because the way the Powershell AD module is installed is different for each 
#               (Add-WindowsCapability for workstations and Add-WindowsFeature for servers).  Also switch from
#               using DISM to native Powershell to install the necessary capabilities/features.
# 20 Feb 2025 : Add check to see if running as Administrator before checking for the ActiveDirectory module.  If
#               not running as Administrator then skip the check.  If the module is not present the script will error out.

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
    [Parameter(mandatory = $true)][pscredential]$Credential  # PSCredential for a user with privilege to create/update a computer object in the target OU
)

########################################################################################

# Check as many of the prerequisites as we can before we do anything.

Write-Verbose ("Checking environment.")

# Verify that the required Powershell modules are installed.  If not, install them.

Write-Verbose ("Verifying that necessary Azure Powershell modules are present.")
$requiredModules = @("Az.Accounts", "Az.Storage", "Az.Resources")
$requiredModules | ForEach-Object {
    if (-not (Get-Module -Name $_ -ListAvailable)) {
        Write-Verbose ("Module $_ is not installed.  Installing it now.")
        Install-Module -Name $_ -Force -Scope CurrentUser
    } else {
        write-verbose ("Module $_ is present.")
    }
}

# Make sure ActiveDirectory module is present.  This requires some features/capabilities to be installed on the system.
# This is done differently on a server vs a workstation (Client)

$WindowsInstallationType = (Get-ComputerInfo).WindowsInstallationType

Write-Verbose ("Windows installation type is `"" + $WindowsInstallationType + "`".")
if ($WindowsInstallationType -ne "Server" -and ($WindowsInstallationType -ne "Client")) {
    Write-Warning ("Unknown WindowsInstallationType value `"$WindowsInstallationType`".  This script may not function correctly.")
}

# Check if we're running as Adminsitrator.  If not then we skip checking for these prereqs which might cause an error later on.
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministratorContext = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not ($isAdministratorContext)) {
    Write-Warning ("This script is not running with elevated privileges.  This will cause errors if the ActiveDirectory module is not present.")
} else {
    # We are running elevated so we can check if the required modules are present.
    if ($WindowsInstallationType -eq "Server") {

        # Server Manager is present by default on a Windows Server (I hope!)
        # Therefore all we need to do is see if the ADDS Powershell module is installed.

        if (((Get-WindowsFeature -Name RSAT-AD-PowerShell).InstallState) -ne "Installed") {
            Write-Verbose ("Installing Active Directory Powershell.  This may take a moment.")
            $result = Add-WindowsFeature RSAT-AD-PowerShell
            if ($result.success) {
                Write-Verbose ("Active Directory Powershell module installed.")
            } else {
                Write-Error ("Unable to install the AD Powershell module.  Please install it manually and try again.")
                exit
            }
            if ($result.RestartNeeded -ne "No") { 
                # This can be "Yes", "No" or "Maybe" (if a restart is pending but not required)
                Write-Warning ("Installer recommends a restart to complete the installation.")
            } else {
                Write-Verbose ("No restart required.")
            }
        }
    } else {
        # This is a workstation (Client) so the required tools are different.

        $serverManagerCapabilityName = "Rsat.ServerManager.Tools~~~~0.0.1.0"
        $ActiveDirectoryRsatModuleCapabilityName = "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"

        $serverManagerPresent= (Get-WindowsCapability -Name $serverManagerCapabilityName -Online).state -eq "Installed"
        $ActiveDirectoryRsatPresent = (Get-WindowsCapability -Name $ActiveDirectoryRsatModuleCapabilityName -Online).state -eq "Installed"

        if (-not ($serverManagerPresent)) {
            Write-Warning ("Server Manager not installed.  Installing...")
            $result = Add-WindowsCapability -Online -Name $ServerManagerCapabilityName
            if ($result.RestartNeeded -ne "No") { # This can be "Yes", "No" or "Maybe" (if a restart is pending but not required)
                Write-Warning ("A restart is recommended to complete the installation of the ServerManager feature.")
            }
        } else {
            Write-Verbose ("Server Manager is present.")
        }

        if (-not ($ActiveDirectoryRsatPresent)) {
            Write-Warning "Active Directory RSAT tools not installed.  Installing..."
            $result = Add-WindowsCapability -Online -Name $ActiveDirectoryRSatModuleCapabilityName
            if ($result.RestartNeeded -ne "No") {
                Write-Warning ("A restart is recommended to complete the installation of the Active Directory RSAT tools.")
            }
        } else { 
            write-verbose ("Active Directory RSAT tools are present.")
        }
    }
}

# Make sure we are connected to Azure
# Using device AuthN to keep things simpler/clearer for the user.
$currentContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $currentContext) {
    write-warning ("Not connected to Azure (no context)`nPlease connect to Azure with Connect-AzAccount.")
    if (Get-Command -Module Az.Accounts Connect-AzAccount) {
        Connect-AzAccount -UseDeviceAuthentication
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

# verify that there is a DC running AD Web Services that we can talk to (AD Cmdlets require this)
$domainControllerIpAddress = (Get-ADDomainController -Discover -Service ADWS -DomainName $ADDomainFQDN).IPv4Address
if (!($domainControllerIpAddress)) { 
	write-error ("Can't find a domain controller running AD Web Services for domain $ADDomainFQDN.  This is necessary for this script to function.")
    Write-Error ("See https://learn.microsoft.com/en-us/services-hub/unified/health/remediation-steps-ad/configure-the-active-directory-web-services-adws-to-start-automatically-on-all-servers for more information.")
	exit
}

# Confirm that the storage account specified actually exists.

# Yes, this method is inefficient and can take several seconds to complete but doing it this way means that we don't need to ask the user for the RG name.
# Since storage account names must be globally unique the chance of getting the "wrong" storage account from this is basically zero.
write-verbose ("Verifying that $storageAccountName exists in the current subscription.  This may take a moment." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName}

if ($null -ne $storageAccount) {
    # First make sure that this storage account is not already configured for ADDS.  If so, exit so we don't touch it.
    Write-verbose "Checking to see if $storageAccountName is already configured for AD authentication."
    if (($storageaccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AD") -and `
        ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName)) {
        Write-Output ("Storage account $storageAccountName is configured to use a different domain " + ($storageaccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName + " for authentication."))
        exit 
    } else {
        # The storage account is not configured for ADDS
        Write-Verbose ("Storage account $storageAccountName is not configured for AD authentication.")
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
Write-Verbose ("Active Directory SPN for this storage account will be $SPN")

# Make sure the target OU DN exists
$domainName = $Domain.dnsroot

$OUlist = Get-ADObject -filter 'DistinguishedName -eq $ADOuDistinguishedName' -Credential $Credential -server $domainName
if ($null -ne $OUlist) {   if (get-ADComputer -Filter { Name -eq $storageAccountName } -Credential $Credential -ErrorAction SilentlyContinue -server $domainControllerIpAddress) {
        write-verbose ("Computer object $storageAccountName is present in $domainName")

        # Since the computer account already exists, update it
        write-verbose ("Updating password for computer object in domain $domainName for $storageAccountName")
        $result = Set-ADAccountPassword -server $domainControllerIpAddress `
                    -Identity ("CN=$storageAccountName,$ADOuDistinguishedName") `
                    -Reset `
                    -NewPassword $CompPassword `
                    -Credential $Credential `
                    -Confirm:$false `
                    -ErrorAction Stop
        Write-Verbose ("Updating existing computer object $storageAccountName in domain $domainName.")
        $result = Set-ADComputer -server $domainControllerIpAddress `
            -Identity ("CN=$storageAccountName,$ADOuDistinguishedName") `
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
            -server $domainControllerIpAddress `
            -path $ADOUDistinguishedName `
            -Description "DO NOT DELETE - Azure File Share Authentication Account" `
            -ServicePrincipalNames $SPN `
            -PasswordNeverExpires $true `
            -OperatingSystem "Azure Files" `
            -AccountPassword $CompPassword `
            -Credential $Credential
        if (-not (get-ADComputer -server $domainControllerIpAddress -Filter { Name -eq $storageAccountName } -Credential $Credential -ErrorAction SilentlyContinue)) {
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

$Computer = Get-ADComputer $storageAccount.StorageAccountName -Credential $Credential -server $domainControllerIpAddress # The computer object in AD for this storage account

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
