# Enable-AzStorageAccountForAzureAdAuthentication.ps1
# by Ken Hoover <ken.dot..hoo verat...micro..soft...dotcom>
# March 2023

# This script configures an Azure Files share to use Azure AD Authentication
# as described at this link https://docs.microsoft.com/en-us/azure/virtual-desktop/create-profile-container-azure-ad


[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$storageAccountName,  # The name of the storage account to configure
    [Parameter(mandatory = $true)][string]$domainName,      # The FQDN of the domain to configure, like "contoso.com"
    [Parameter(mandatory = $true)][string]$domainGUID      # The GUID (ObjectID) for the domain
)   


<#
.SYNOPSIS

This script configures an Azure Files share for authentication using Azure AD Kerberos.

.DESCRIPTION

This script configures an Azure Storage account for authentication via Azure AD Kerberos as described at https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-azure-active-directory-enable?tabs=azure-portal

To use it, follow these steps:

...

.PARAMETER storageAccountName

The name of the storage account to configure.  The storage account must exist and have a name which is 15 characters or less in length to avoid legacy NetBIOS naming issues.

.PARAMETER domainName

The full name of the AD domain to work with, like "ad.contoso.com"

.PARAMETER doimainGuid

The GUID of the AD domain listed above.  You can get this from Get-AdDomain, for example.

.EXAMPLE

...

.LINK
    https://www.github.com/hooverken/ARM-Powershell
#>
function Set-AdminConsent {
    # Thanks to teammate and generally awesome guy Sven Aelterman for the below function to
    # silently do the admin consent grant via a REST call
    # (assuming you're logged in with the correct privilges of course!)

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$applicationId,
        [Parameter(Mandatory)][object]$context  # The Azure Context]
    )

    $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
        $context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "74658136-14ec-4630-ad9b-26e160ff0fc6")

    $headers = @{
        'Authorization'          = 'Bearer ' + $token.AccessToken
        'X-Requested-With'       = 'XMLHttpRequest'
        'x-ms-client-request-id' = [guid]::NewGuid()
    }

    $url = "https://main.iam.ad.ext.azure.com/api/RegisteredApplications/$applicationId/Consent?onBehalfOfAll=true"

    $result = Invoke-RestMethod -Uri $url -Headers $headers -Method POST -ErrorAction Stop

    return $result
}

######################### MAIN PROGRAM EXECUTION BEGINS BELOW ##############################

# Confirm that the storage account specified actually exists
# Yes, this method is slow but it means that we don't need to ask the user for the resource group name of the storage account
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }

if ($storageAccount) {
    Write-Verbose ("Storage account $storageAccountName is present")
} else {
    Write-Warning ("Storage account $storageAccountName not found in current subscription.")
    exit
}

# Enable the storage account for Azure AD Kerberos authentication
Write-Verbose ("Enabling AD Kerberos for Files on $storageAccountName.")
$result = Set-AzStorageAccount -ResourceGroupName $storageAccount.ResourceGroupName -StorageAccountName $storageAccount.StorageAccountName -EnableAzureActiveDirectoryKerberosForFile $true -ActiveDirectoryDomainName $domainName -ActiveDirectoryDomainGuid $domainGuid

if (!($result)) {
    Write-Warning ("Failed to enable AD Kerberos for Files on $storageAccountName.")
    exit
}

# wait a few seconds for things to propagatge
Write-Verbose ("Waiting for app registration to appear in AAD...")  
do {
    Start-Sleep -Seconds 5
    Write-Verbose ("5 seconds...")
    $application = Get-AzADApplication | Where-Object { $_.DisplayName.EndsWith($storageAccount.PrimaryEndpoints.file.split('/')[2])}
} while (!$application)

# To make sure things have settled, use the application ID to look up the app in the other direction
do {
    Write-Verbose ("App registration is confirmed in AAD.  Waiting 30s more for AAD propagation before proceeding...")
    Start-Sleep -Seconds 30
} until ($null -ne (Get-AzADApplication -ApplicationId $application.AppId))

# We need to grant admin consent to the newly created App to read the logged-in user's information.
Write-Verbose ("Applying required admin consent for application ID " + $application.AppId)

$consentResult = Set-AdminConsent -applicationId $application.AppId -context (Get-AzContext)

$consentResult
# That's it.  

# TODO: How can we verify that this has been done??