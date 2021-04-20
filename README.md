# ARMPowershell
Miscellaneous Powershell scripts for use with Azure ARM

## Contents

* **Configure-AzFilesForADDSandFSLogix.ps1** - Configures an Azure Files share for use with FSLogix including IAM role assignments and NTFS permissions.
* **Configure-AzFilesForADDSAuthN.ps1** - Configures an Azure storage account to use [Active Directory (ADDS) authentication](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable).  This is intended as an alternative to the AzFilesHybrid module wihich is referenced in the above link.
* **Configure-AzFilesForMSIXAppAttach.ps1** - Configures an Azure Files share permissions for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Windows Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/)
* **Exterminate-AzureVM.ps1** - Deletes all elements of an Azure VM (compute, OS disk, data disks and NICs)


All scripts support the `-Verbose` parameter.  It is recommended to use this to view progress as the scripts run.

---
# Configure-AzFilesForADDSandFSLogix.ps1

This is intended for use in scenarios where you are configuring [Windows Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) environments to work with [FSLogix Profile containers](https://docs.microsoft.com/en-us/fslogix/configure-profile-container-tutorial) stored on file shares in [Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/) as the location for the profile share and Active Directory Domain services (NOT Azure Active Directory Domain Services!) as the authentication mechanism.

It handles does the necessary configuration in both the local AD and in Azure so once you run it (cleanly) you can move on to FSLogix installation and configuration.

This is intended for use in place of the [AzFilesHybrid Powershell module](https://github.com/Azure-Samples/azure-files-samples/releases) which myself and others have found to be clunky and unreliable.  This script works by automating the approach described in the "manual" steps to configure the storage account.

This script will create a computer object in AD to represent the Kerberos identity for authentication.  The computer object will have the same username as the storage account.  **Do not delete this object** or you will break the ADDS authentication

This script is based on work by John Kelbley, a member of the GBB team at Microsoft.

The script does do a fair amount of sanity checking to avoid "normal" errors but is not bulletproof.


## Parameters

### storageAccountName

<ul>
The name of the storage account that holds the Azure Files share.

ADVISORY: The name of the storage account must be 15 characters or less to avoid legacy netBIOS issues.  Execution will be halted if the storage account name exceeds this limit.
</ul>

### profileShareName

<ul>
The name of the Azure Files share that you will use for FSLogix profiles.

If the share does not exist in the specified storage account, it will be created.
</ul>

### ADOuDistinguishedName

<ul>The full DN of an OU for the new computer object to be created in.

Example: `OU=WVD,DC=contoso,DC=com`
</ul>

### ShareAdminGroupName
<ul>
The name of an AD group that will be granted the "Storage File Data SMB Share Elevated Contributor" IAM role on the Azure Files share.

The membership of this group should be people who will need full access to see the contents of the Profiles share for some reason.
</ul>

### ShareUserGroupName
<ul>
The name of an AD group which will be granted the "Storage File Data SMB Share Elevated Contributor" IAM role on the Azure Files share.

This group should contain _all users that will be using the FSLogix profile sharing environment_ (e.g. all WVD users).
</ul>

### IsGovCloud (ONLY FOR Azure Gov Cloud)
<ul>
Add this parameter if you are working in Azure Gov Cloud.  This is necessary because the SPN format for the kerberos configuration is different between the public and government clouds.

![Screenshot](https://github.com/hooverken/ARMPowershell/blob/main/Configure-AzFilesForADDSAuthNScreenshot.PNG)
</ul>
---

# Configure-AzFilesForADDSAuthentication.ps1

This script configures an Azure storage account to use Active Directory (ADDS) for authentication.

It does the necessary configuration in both the local AD and in Azure so once you run it (cleanly) it should work as expected. 

Like the one above, this is intended for use in place of the [AzFilesHybrid Powershell module](https://github.com/Azure-Samples/azure-files-samples/releases) which myself and others have found to be cranky and unreliable.

It will create a computer object in AD to represent the Kerberos identity for authentication.  The computer object will have the same username as the storage account.  Do not annoy, molest, feed or otherwise disturb this account as it will break authentication.

This is based on earlier work by John Kelbley, a WVD GBB at Microsoft, which parallels the steps under "Option 2" of the [documentation](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-enable#option-2-manually-perform-the-enablement-actions) for enabling ADDS Authentication for Azure Files shares.

The script does do a fair amount of sanity checking to avoid "normal" errors but is not bulletproof.

It is strongly recommended to run with the `-Verbose` parameter for more detail on what it is doing.

## Parameters

### storageAccountName
<ul>
The name of the storage account that holds the Azure Files share.

The name of the storage account must be 15 characters or less to avoid legacy netBIOS issues.
</ul>

### ADOuDistinguishedName
<ul>
The full DN of an OU for the new computer object to be created in.

Example: `OU=MyOUName,DC=contoso,DC=com`
</ul>

### IsGovCloud (ONLY FOR Azure Gov Cloud)
<ul>
Add this parameter if you are working in Azure Gov Cloud.  This is necessary because the SPN format for the kerberos configuration is different between the public and government clouds.
</ul>

---

# Configure-AzFilesForMSIXAppAttach.ps1

This script applies the necessary permissions (both IAM role assignments and NTFS ACLs) to configure an [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/) share for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Windows Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/).

## Parameters

### storageAccountName
<ul>The name of the storage account for the file share
### shareName
The name of the file share to configure.  If this share does not exist, it will be created.
</ul>

### AppAttachSessionHostManagedIdAADGroupName
<ul>The name of an **Azure AD group** containing the managed identities of the WVD session hosts that will be using the share.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.
</ul>

### AppAttachUsersADDSGroupName
<ul>The name of an **onprem AD group** containing the managed identities of the WVD session hosts that will be using the share.  This group must be synchronized to Azure AD.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.
</ul>

### AppAttachComputersADDSGroupName
<ul>The name of an **onprem AD group** containing the computer objects of the WVD session hosts that will be using the share.  This group must be synchronized to Azure AD.  This group will be granted the [Storage File Data SMB Data Reader](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-file-data-smb-share-reader) IAM role on the share.
</ul>

### IsGovCloud
<ul>*This parameter is optional.  If not specified the default is to use the Azure commercial cloud.*

If you are working with a US Gov Cloud Azure environment, add this parameter to the command line.  This is necessary because the Azure Files endpoint name suffixes are different for Giv cloud vs the commercial (public) cloud.
</ul>
---

# Exterminate-AzureVM.ps1

This script deletes all of the (major) components of a VM:
* Compute instance
* OS disk
* All data disks
* All NICs

It works by finding the VM object and then looking at the OSProfile, storageProfile and the networkProfile properties of the VM to find the disks and NICs associated with the VM and then deleting them.

This is intended to make cleanup easier when messing around with machines for sandboxing etc.  

**The deletes are NOT UNDOABLE so use with care.**