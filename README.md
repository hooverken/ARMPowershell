# ARMPowershell
Miscellaneous Powershell scripts for use with Azure ARM

## Contents

* (Updated Sept 2022) **Configure-AzStorageAccountForADDSAuthN.ps1** Configures an Azure storage account to use [Active Directory (ADDS) authentication](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable).  This is a simpler alternative to the AzFilesHybrid module wihich is referenced in the above link.<br><br>
* (Updated Sept 2022) **Configure-AzFilesShareForFSLogixProfileContainers.ps1** Sets up a file share on an Azure storage account and configures it for use with [FSlogix profile containers](https://docs.microsoft.com/en-us/azure/virtual-desktop/fslogix-containers-azure-files).<br><br>
* **Configure-AzFilesShareForMSIXAppAttach.ps1** - Configures an Azure Files share permissions for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/)<br><br>
* **Get-AvdHostPoolBilledCharges.ps1** - Takes the name of an [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) host pool as a parameter and returns the actual billed charges for the compute and disk resources for a given time span (default prior 30 days if no start/end date specified).<br><br>
* **Exterminate-AzureVM.ps1** - Deletes all elements of an Azure VM (compute, OS disk, data disks and NICs)

All scripts support the `-Verbose` parameter.  It is recommended to use this to view progress as the scripts run.

---

# Configure-AzStorageAccountForADDSAuthN.ps1


This script configures an Azure storage account to use AD Domain Services (ADDS) Authentication as described [here](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable).  It handles the necessary configuration in both the local AD and in Azure.

This is intended for use in place of the [AzFilesHybrid Powershell module](https://github.com/Azure-Samples/azure-files-samples/releases) which I've found to be clunky and unreliable.  The script works by automating the manual approach described in the "Option 2" steps in the link above to configure the storage account.

This script will create a computer object in the local AD to represent the storage account for Kerberos authentication.  The computer object will have the same name as the storage account.  **Do not delete this object** or you will break the ADDS authentication.  As a suggestion, create an OU dedicated to holding these special computer objects.

This is based on prior work by John Kelbley, a member of the GBB team at Microsoft.


### **Prerequisites**

* Powershell 7 or higher is required.
* The system that you are running this script from must be joined to the same AD that you want to bind to the storage account
* The script needs the `Az.Accounts`, `Az.Resources` and `Az.Storage` modules and also the `ActiveDirectory` module to function.  If they are not present the script will attempt to install them.  The ActiveDirectory module is part of the RSAT tools for Windows which are installed using DISM.


### How to use

1. Gather the following information:
    * The **name of the storage account** to configure
    * The full **DistinguishedName (DN)** of the OU to create the new computer object in.
2. Log in as a domain user with permission to add a computer to the specified OU.
3. Connect to Azure with `Connect-AzAccount` as a user with permission to configure the target storage account
4. Run the script using a command line like this one<br> `Configure-AzStorageAccountForADDSAuthN.ps1 -storageAccountName "myStorageAccount" -ADOuDistinguishedName "OU=MyOU,DC=MyDomain,DC=local" -Verbose`

Using the `-Verbose` parameter will show detailed progress of the script as it runs.

## **Parameters**

### **storageAccountName**

The name of the target storage account. The name must be 15 characters or less in length to avoid difficult-to-diagnose legacy netBIOS issues.  This can be a challenge in environments with elaborate naming conventions.

### **ADOuDistinguishedName**
The full DistinguishedName (DN) of the OU for the new computer object to be created in.

Example: `OU=Azure Storage Accounts,DC=contoso,DC=com`

![Screenshot](https://github.com/hooverken/ARMPowershell/blob/main/Configure-AzStorageAccountForADDSAuthN.png?raw=true)

---

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

# Get-AvdHostPoolBilledCharges.ps1

This script takes the name of an [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) host pool as a parameter and returns the actual billed charges for the compute and disk resources for a given time span (default prior 30 days if no start/end date specified).

Due to the way that the billing API returns data, there will likely be multiple lines per resource, each with its own time period, since utilization for a resource may not cover an entire day.

The output is a list of objects with the following properties:

* **resourceName** (string) The name of the resource
* **pretaxCost** (decimal) The billed charge for the resource
* **resourceType** (string) The type of the billed item.  This will be `Microsoft.Compute/virtualMachines` for Compute and `Microsoft.Compute/disks` for managed disks.
* **UsageStart** (dateTime) The start of the billing period for the line item
* **UsageEnd** (dateTime) The end of the billing period for the line item
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

