# Rotate-LetsEncryptCertificate.ps1
# Original version Ba Ali Raza on LinkedIn
# Ref: https://www.linkedin.com/pulse/automating-lets-encrypt-ssl-certificate-renewal-azure-ali-raza-ckzje/

# Modified by Ken Hoover <moc.tfosorcim@revooh.nek>
# October 2025

# Note: The original script rotated a certificate in an Azur App Gateway.
# This version has been changed to rotate the certificate in a key vault.


#######################################################################
# Script that renews a Let's Encrypt certificate for an Azure Application Gateway
# Pre-requirements:
#      - Have a storage account in which the folder path has been created:
#        '/.well-known/acme-challenge/', to put here the Let's Encrypt DNS check files
 
#      - Add "Path-based" rule in the Application Gateway with this configuration:
#           - Path: '/.well-known/acme-challenge/*'
#           - Check the configure redirection option
#           - Choose redirection type: permanent
#           - Choose redirection target: External site
#           - Target URL: <Blob public path of the previously created storage account>
#                - Example: 'https://test.blob.core.windows.net/public'
#      - For execution on Azure Automation: Import 'AzureRM.profile', 'AzureRM.Network'
#        and 'ACMESharp' modules in Azure
######################################################################

[CmdletBinding()]

Param(
    [Parameter(Mandatory=$true)][string]$domainName,
    [Parameter(Mandatory=$true)][string]$emailAddress,
    [Parameter(Mandatory=$true)][string]$keyVaultRGName,
    [Parameter(Mandatory=$true)][string]$keyVaultName
)

# Installs the ACME module if it's not present.
# This module works with the ACME protocol to rotate certificates
if (-not (Get-Module -Name ACME-PS -ListAvailable)) {
    Install-Module -Name ACME-PS -Force -Scope CurrentUser
}

# turn off autosaving of credentials by the Az Powershell module
Disable-AzContextAutosave

if (Get-AzContext) {
    Write-Host "Using existing Az context"
} else {
    Write-Host "Logging in to Azure using service identity"
    Connect-AzAccount -Identity
}

# Create a new ACMEstate object
$state = New-ACMEState -Path $env:TEMP
$serviceName = 'LetsEncrypt'

Get-ACMEServiceDirectory $state -ServiceName $serviceName -PassThru;

New-ACMENonce $state;

New-ACMEAccountKey $state -PassThru;

New-ACMEAccount $state -EmailAddresses $EmailAddress -AcceptTOS;

$state = Get-ACMEState -Path $env:TEMP;

New-ACMENonce $state -PassThru;

$identifier = New-ACMEIdentifier $domain;

$order = New-ACMEOrder -State $state -Identifiers $identifier;

if ($null -eq $order) { # Will fetch the order

 $order = Find-ACMEOrder -State $state -Identifiers $identifier;

}

$authZ = Get-ACMEAuthorization -State $state -Order $order;

$challenge = Get-ACMEChallenge -State $state -Authorization $authZ -Type "http-01";

$fileName = $env:TMP + '\' + $challenge.Token;

Set-Content -Path $fileName -Value $challenge.Data.Content -NoNewline;

$blobName = ".well-known/acme-challenge/" + $challenge.Token

$storageAccount = Get-AzStorageAccount -ResourceGroupName $STResourceGroupName -Name $storageName

$ctx = $storageAccount.Context

Get-AzStorageContainerAcl -Name "public" -Context $ctx

Set-AzStorageBlobContent -File $fileName -Container "public" -Context $ctx -Blob $blobName

Get-AzStorageBlob -Container "public" -Context $ctx -Blob $blobName

$challenge | Complete-ACMEChallenge -State $state;

while($order.Status -notin ("ready","invalid")) {

 Start-Sleep -Seconds 10;

 $order | Update-ACMEOrder -State $state -PassThru;

}

if($order.Status -ieq ("invalid")) {

 $order | Get-ACMEAuthorizationError -State $state;

 throw "Order was invalid";

}

$certKey = New-ACMECertificateKey -Path "$env:TEMP\$domain.key.xml";

 

Complete-ACMEOrder -State $state -Order $order -CertificateKey $certKey;

while(-not $order.CertificateUrl) {

 Start-Sleep -Seconds 15

 $order | Update-ACMEOrder -State $state -PassThru

}

$password = ConvertTo-SecureString -String "**********" -Force -AsPlainText

Export-ACMECertificate $state -Order $order -Certificate