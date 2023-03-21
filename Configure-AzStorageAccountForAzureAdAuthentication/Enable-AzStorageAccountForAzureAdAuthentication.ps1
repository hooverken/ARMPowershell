# Configure-AzStorageAccountForAzureAdAuthentication.ps1
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


# Thanks to teammate and generally awesome guy Sven Aelterman for the below function to
# silently do the admin consent grant via a REST call
# (assuming you're logged in with the correct privilges of course!)

function Set-AdminConsent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$applicationId,
        [Parameter(Mandatory)][object]$context  # The Azure Context]
    )

    $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
        $context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "74658136-14ec-4630-ad9b-26e160ff0fc6")

    $token | Get-Member

    $headers = @{
        'Authorization'          = 'Bearer ' + $token.AccessToken
        'X-Requested-With'       = 'XMLHttpRequest'
        'x-ms-client-request-id' = [guid]::NewGuid()
    }

    $url = "https://main.iam.ad.ext.azure.com/api/RegisteredApplications/$applicationId/Consent?onBehalfOfAll=true"

    Invoke-RestMethod -Uri $url -Headers $headers -Method POST -ErrorAction Stop -verbose
}

######################### MAIN PROGRAM EXECUTION BEGINS BELOW ##############################

# Confirm that the storage account specified actually exists
# Yes, this method is slow but it means that we don't need to ask the user for the resource group name of the storage account
write-verbose ("Verifying that $storageAccountName exists.  This will take a moment..." )
$storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }

Write-Verbose ("Verifying that we can connect to the storage account")
if ($storageAccount) {
    $storageAccountResourceId = $storageAccount.Id
    Write-Verbose ("Storage account $storageAccountName resource ID is $storageAccountResourceId")
} else {
    Write-Warning ("Storage account $storageAccountName not found in current subscription.")
    exit
}

# Enable the storage account for Azure AD Kerberos authentication
Set-AzStorageAccount -ResourceGroupName $storageAccount.ResourceGroupName -StorageAccountName $storageAccount.StorageAccountName -EnableAzureActiveDirectoryKerberosForFile $true -ActiveDirectoryDomainName $domainName -ActiveDirectoryDomainGuid $domainGuid

# We need to grant admin consent to the newly created App to read the logged-in user's information.
$application = Get-AzADApplication | where { $_.DisplayName.EndsWith($storageAccount.PrimaryEndpoints.file.split('/')[2])}
$ApplicationID = $application.AppId

Set-AdminConsent -applicationId $ApplicationID -context (Get-AzContext)

# That's it.  How can we verify that this has been done??