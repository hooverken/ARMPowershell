# Enable-AzStorageAccountForAzureAdAuthentication.ps1

A script to configure an Azurte storage account for AzureAD Kerberos authentication using the procedure described [here](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-azure-active-directory-enable?tabs=azure-portal).

## Prerequisites / Assumptions

* You need Powershell 7 installed
* The `Az` and `AzureAD` modules are installed
* Your Powershell session is connected to Azure using `Connect-AzAccount`
* 

## Parameters

### storageAccountName

the name of the storage account, like `mystorageaccount001`

### domainName

The name of the AD domain to use for authentication like `ad.contoso.com`

### domainGUID

The ObjectGUID of the AD domain to use for authentication like `12345678-1234-1234-1234-123456789012`.

You can get this from `Get-AdDomain` in PowerShell.