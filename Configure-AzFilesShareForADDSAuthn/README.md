# Configure-AzStorageAccountForADDSAuthN.ps1

This script configures an Azure storage account to use AD Domain Services (ADDS) Authentication as described [here](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable).  It handles the necessary configuration in both the local AD and in Azure.

This is intended for use in place of the [AzFilesHybrid Powershell module](https://github.com/Azure-Samples/azure-files-samples/releases) which I've found to be clunky and unreliable.  The script works by automating the manual approach described in the "Option 2" steps in the link above to configure the storage account.

This script will create a computer object in the local AD to represent the storage account for Kerberos authentication.  The computer object will have the same name as the storage account.  **Do not delete this object** or you will break the ADDS authentication.  As a suggestion, create an OU dedicated to holding these special computer objects.

This is based on prior work by John Kelbley, a member of the GBB team at Microsoft.

### **Prerequisites**

* Powershell 7 or higher is required.
* The system that you are running this script from must be joined to the same AD that you want to bind to the storage account
* The script needs the `Az.Accounts`, `Az.Resources` and `Az.Storage` modules and also the `ActiveDirectory` module to function.  If they are not present the script will attempt to install them.  The ActiveDirectory module is part of the RSAT tools for Windows which will be installed using DISM if they are not present.

### How to use

1. Gather the following information:
    * The **name of the storage account** to configure
    * The full **DistinguishedName (DN)** of the OU to create the new computer object in.
2. Log in as a domain user who has permission to add a computer to the specified OU.
3. Connect to Azure with `Connect-AzAccount` as a user with permission to configure the target storage account
4. Run the script using a command line like this one<br> `Configure-AzStorageAccountForADDSAuthN.ps1 -storageAccountName "myStorageAccount" -ADOuDistinguishedName "OU=MyOU,DC=MyDomain,DC=local" -Verbose`

Using the `-Verbose` parameter will show detailed progress of the script as it runs.

## **Parameters**

### **storageAccountName**

The name of the target storage account. The name must be 15 characters or less in length to avoid difficult-to-diagnose legacy netBIOS issues.  This can be a challenge in environments with elaborate naming conventions.

### **ADOuDistinguishedName**

The full DistinguishedName (DN) of the OU for the new computer object to be created in.

Example: `OU=Azure Storage Accounts,DC=contoso,DC=com`

![Screenshot](https://github.com/hooverken/ARMPowershell/blob/main/Configure-AzFilesShareForADDSAuthn/Configure-AzStorageAccountForADDSAuthN.png?raw=true)