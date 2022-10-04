# Configure-AzFilesShareForFSLogixProfileContainers.ps1

This script works against an Azure storage account to configure an [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/) share for use with [FSLogix Profile Containers](https://docs.microsoft.com/en-us/azure/virtual-desktop/create-file-share) by applying the necessary IAM roles and NTFS permissions.


## **Prerequisites**

The following things should be true of the system that you are using to run the script:
* PowerShell 7 is required.  This is not installed by default in most cases.  You can download the current version of PowerShell for Windows from [here](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).
* The system running the script must have network visibility to the Azure Files share on port 445 (SMB).
* The script uses a few pieces of [Az PowerShell module](https://learn.microsoft.com/en-us/powershell/azure/new-azureps-module-az): `Az.Accounts`, `Az.Resources` and `Az.Storage`.  If these are not present in the local system they will be installed automatically with scope `CurrentUser`.

### How to use

1. Gather the following information:
    * The **name of the storage account** to configure
    * The **share name**.  If the share doesn't exist then it will be created.
    * The name of an **AD group for unprivileged users that will access the share** in an ordinary capacity (e.g. nonprivileged users).  This group will be assigned the built-in Azure role `Storage File Data SMB Share Contributor` which allows basic CRUD actions on files inside the share.
    * The name of an **AD group for privileged users** (e.g. admins).  These users will be able to work with other users' profile VHDs.  This group will be assigned the built-in Azure role `Storage File Data SMB Share Elevated Contributor` which allows them to perform all operations on the share.
2. Connect to Azure with `Connect-AzAccount` as a user with permission to configure the target storage account
3. Run the script using a command line like this one<br>`Configure-AzStorageAccountForADDSSuthN.ps1 -storageAccountName "myStorageAccount" -profileSharename myprofiles -userGroup "MyUsers" -adminGroup "MyAdmins" -Verbose`

Using the `-Verbose` parameter will show detailed progress of the script as it runs.


## Parameters

### **storageAccountName** (string)
The name of the storage account that holds the Azure Files share.  It is assumed that this share is configured for ADDS authentication.

### **ProfileShareName** (string)

The name of the file share to configure.  If this share name does not exist it will be created for you.  If the filename contains mixed case characters the name will be converted to all-lowercase as required by Azure Files.  For the full list of share name constraints see [this link](https://docs.microsoft.com/en-us/rest/api/storageservices/naming-and-referencing-shares--directories--files--and-metadata#share-names)


### **ShareAdminGroupName** (string)
The name of an Active directory group which contains users that should have privileged (full control) access to the Azure Files share.  This group must be synced to Azure AD.  It will be assigned IAM role [Storage File Data SMB Share Elevated Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-elevated-contributor)

### **ShareUserGroupName** (string)
The name of an Active directory group which contains end users that will have their profiles stored on the Azure Files share.  This group must be synced to Azure AD.  It will be assigned IAM role [Storage File Data SMB Share Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-contributor)

![Screenshot](https://github.com/hooverken/ARMPowershell/blob/main/Configure-AzFilesShareForFSLogixProfileContainers/Configure-AzFilesShareForFSLogixProfileContainers.png?raw=true)