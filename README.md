# ARMPowershell
Miscellaneous Powershell scripts for use with Azure ARM

## Contents

* **Configure-AzStorageAccountForADDSAuthN.ps1** - Configures an Azure storage account to use [Active Directory (ADDS) authentication](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable).  This is intended as an alternative to the AzFilesHybrid module wihich is referenced in the above link.<br><br>
* **Configure-AzFilesShareForFSLogixProfileContainers.ps1** - Applies the necessary IAM role assignments and NTFS permissions structure for an [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/) share to work correctly with [FSlogix profile containers](https://docs.microsoft.com/en-us/azure/virtual-desktop/fslogix-containers-azure-files).<br><br>
* **Configure-AzFilesShareForMSIXAppAttach.ps1** - Configures an Azure Files share permissions for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/)<br><br>
* **Get-AvdHostPoolBilledCharges.ps1** - Takes the name of an [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) host pool as a parameter and returns the actual billed charges for the compute and disk resources for a given time span (default prior 30 days if no start/end date specified).<br><br>
* **Exterminate-AzureVM.ps1** - Deletes all elements of an Azure VM (compute, OS disk, data disks and NICs)


All scripts support the `-Verbose` parameter.  It is recommended to use this to view progress as the scripts run.

---

# Configure-AzStorageAccountForADDSAuthN.ps1


This script configures an Azure storage account for ADDS Authentication as described [here](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable).  It handles the necessary configuration in both the local AD and in Azure.

This is intended for use in place of the [AzFilesHybrid Powershell module](https://github.com/Azure-Samples/azure-files-samples/releases) which myself and others have found to be clunky and unreliable.  It works by automating the approach described in the "manual" steps to configure the storage account.

This script will create a computer object in the local AD to represent the Kerberos identity for authentication.  The computer object will have the same username as the storage account.  **Do not delete this object** or you will break the ADDS authentication

This script is based on prior work by John Kelbley, a member of the GBB team at Microsoft.

## **Prerequisites**

It's best to run this script from an AD domain controller.

* Make sure you are connected to the target Azure environment using the Az Powershell module
* Must be connected to Azure as a user that has the ability to configure the storage account (e.g. `Owner`)
* The ActiveDirectory Powershell module must be installed
* Your Powershell session must be running in an elevated (Administrator) context
* You must have have permission to create computer objects in the target OU


## **Parameters**

### **storageAccountName**

The name of the target storage account. The name of the storage account must be 15 characters or less in length to avoid legacy netBIOS issues.  This can be a challenge in environments with complex naming conventions.

### **ADOuDistinguishedName**
The full DN of an OU for the new computer object to be created in.

Example: `OU=MyOUName,DC=contoso,DC=com`

### **IsGovCloud** (ONLY FOR Azure Gov Cloud)
Add this parameter if you are working in Azure Gov Cloud.  This is necessary because the SPN format for the kerberos configuration is different between the public and government clouds.

![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/ConfigureAzStorageAccountForADDAuthNScreenshot.PNG)

---

# Configure-AzFilesShareForFSLogixProfileContainers.ps1

This script applies the necessary Azure IAM role assignments and NTFS ACLs changes to configure an [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/) share for use with [FSLogix Profile Containers](https://docs.microsoft.com/en-us/azure/virtual-desktop/create-file-share). 

It is strongly recommended to run with the `-Verbose` parameter for more detail on what it is doing.

## **Prerequisites**

It's best to run this script from a system that is joined to the same AD that the Azure Files share is using for ADDS authentication.

* Make sure you are connected to the target Azure environment using the Az Powershell module as a user which can create a file share on the target storage account
* ALSO make sure you are connected to Azure AD with `Connect-AzureAD`
* The ActiveDirectory Powershell module must be installed

## Parameters

### **storageAccountName**
The name of the storage account that holds the Azure Files share.  It is assumed that this share is configured for ADDS authentication.

### **ProfileShareName**

The name of the file share to use.  If this share name does not exist it will be created for you.  If the filename contains mixed case characters it will be converted to all-lowercase as required by Azure Files.<br><br>  For the full list of share name constraints see [this link](https://docs.microsoft.com/en-us/rest/api/storageservices/naming-and-referencing-shares--directories--files--and-metadata#share-names)


### **ShareAdminGroupName**
The name of an Active directory group which contains users that should have privileged (full control) access to the Azure Files share.  This group must be synced to Azure AD.

### **ShareUserGroupName**
The name of an Active directory group which contains end users that will have their profiles stored on the Azure Files share.  This group must be synced to Azure AD.

![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Configure-AzFilesShareForFSLogixProfileContainers.PNG)

---

# Configure-AzFilesShareForMSIXAppAttach.ps1

This script applies the necessary permissions (both IAM role assignments and NTFS ACLs) to configure an [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/) share for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/).

## Prerequisites

It's best to run this script from a system that is joined to the same AD that the storage account is using for authentication.

* Make sure you are connected to the target Azure environment using the Az Powershell module as a user which can create a file share on the target storage account
* ALSO make sure you are connected to Azure AD with `Connect-AzureAD`
* The ActiveDirectory Powershell module must be installed


## Parameters

### **storageAccountName**
The name of the storage account for the file share

### **shareName**

The name of the file share to use.  If this share name does not exist it will be created for you.  If the share name contains mixed case characters it will be converted to all-lowercase as required by Azure Files.  <br><br>For the full list of Azure Files share name constraints see [this link](https://docs.microsoft.com/en-us/rest/api/storageservices/naming-and-referencing-shares--directories--files--and-metadata#share-names)


### **AppAttachSessionHostManagedIdAADGroupName**
The name of an **Azure AD group** containing the [system-managed identities](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-managed-identities-work-vm) of the WVD session hosts that will be using the share.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.<br><br>
IMPORTANT:  These identities are **not the same thing** as device objects that are synced from onprem AD (if device sync is enabled)


### **AppAttachUsersADDSGroupName**
The name of an <b>onprem AD group</b> containing the managed identities of the WVD session hosts that will be using the share.  This group must be synchronized to Azure AD.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.

### **AppAttachComputersADDSGroupName**
The name of an <b>onprem AD group</b> containing the computer objects of the WVD session hosts that will be using the share.  This group must be synchronized to Azure AD.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.

### **IsGovCloud**
<b>This parameter is optional.  If not specified the default is to use the Azure commercial cloud</b><br>

If you are working with a US Gov Cloud Azure environment, add this parameter to the command line.  This is necessary because the Azure Files endpoint name suffixes are different for Gov cloud vs the commercial (public) cloud.
</ul>

![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Configure-AzFilesShareForMSIXAppAttach.PNG)
---

# Get-AvdHotPoolBilledCharges.ps1

This script takes the name of an [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) host pool as a parameter and returns the actual billed charges for the compute and disk resources for a given time span (default prior 30 days if no start/end date specified).

Due to the way that the billing API returns data, there will likely be multiple lines per resource, each with its own time period, since utilization for a resource may not cover an entire day.

The output is a list of objects with the following properties:

* **resourceName** (string) The name of the resource
* **pretaxCost** (double) The billed charge for the resource
* **resourceType** (string) The type of the billed item.  This will be `Microsoft.Compute/virtualMachines` for Compute and `Microsoft.Compute/disks` for managed disks.
* **resourceId** (string) The full resource ID of the billed resource

## Prerequisites

* Make sure that the current session context is pointing to the correct Azure subscription


## Parameters

### **AVDHostPoolName**
The name of the AVD Host Pool to examine

### **startDate** and **endDate**

dateTime values defining the date range to return data from.  If either the start or end date is not provided,  then the default is to use data from the prior 30 days.

*IMPORTANT: Billing data can lag by a few days so cost information for charges incurred less than 48 hours ago may not be accurate (or even present).*<br><br>

Sample Output (may not exactly match)
![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Get-AvdHostPoolBilledCharges-Output-Screeenshot.png)

# Exterminate-AzureVM.ps1

This script deletes all of the (major) components of a VM:
* Compute instance
* OS disk
* All data disks
* All NICs

It works by retrieving the VM object from Azure and then looking at the OSProfile, storageProfile and the networkProfile properties to find the disks and NICs associated with the VM and then deleting them.

This is intended to make cleanup easier when messing around with machines for sandboxing etc.  

Backups of the target VM in a Recovery Vault or similar service, are not affected and will need to be removed manually.

**The deletes are NOT UNDOABLE so use with care.**

## Parameters

### **VirtualMachineName**

The name of the VM to exterminate

