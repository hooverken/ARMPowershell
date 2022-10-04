# Configure-AzFilesShareForMSIXAppAttach.ps1

This script applies the necessary permissions (both IAM role assignments and NTFS ACLs) to configure an [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/) share for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/).

## Prerequisites

It's best to run this script from a system that is joined to the same AD that the storage account is using for authentication.

* Make sure you are connected to the target Azure environment (with `Connecct-AzAccount`) as a user which can create a file share on the target storage account
* The ActiveDirectory Powershell module must be installed.  If it is not present it will be installed automatically using DISM.

## Parameters

### **storageAccountName**

The name of the storage account for the file share

### **shareName**

The name of the file share to use.  If this share name does not exist it will be created for you.  If the share name contains mixed case characters it will be converted to all-lowercase as required by Azure Files.  <br><br>For the full list of Azure Files share name constraints see [this link](https://docs.microsoft.com/en-us/rest/api/storageservices/naming-and-referencing-shares--directories--files--and-metadata#share-names)

### **AppAttachUsersADDSGroupName**
The name of an <b>onprem AD group</b> containing the managed identities of the session hosts that will be using the share.  This group must be synchronized to Azure AD.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.

### **AppAttachComputersADDSGroupName**
The name of an <b>onprem AD group</b> containing the computer objects of the session hosts that will be using the share.  This group must be synchronized to Azure AD.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.

### **ADCredential**
a PSCredential object containing the credentials fgor a user which has permission to read from the target AD.

![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Configure-AzFilesShareForMSIXAppAttach/Configure-AzFilesShareForMSIXAppAttach.PNG)