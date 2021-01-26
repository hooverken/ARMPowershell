# ARMPowershell
Miscellaneous Powershell scripts for use with Azure ARM

## Contents

* Configure-AzFilesForADDSAuthentication.ps1 - Sets up your Azure Files share for use with FSLogix
* Exterminate-AzureVM.ps1 - Deletes all elements of an Azure VM (compute, OS disk, data disks and NICs)

***

# Configure-AzFilesForADDSAuthentication.ps1

## Description

This script is intended for use in scenarios where you are configuring [Windows Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) environments to work with [FSLogix Profile containers](https://docs.microsoft.com/en-us/fslogix/configure-profile-container-tutorial) stored on file shares in [Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/) as the location for the profile share and Active Directory Domain services (NOT Azure Active Directory Domain Services!) as the authentication mechanism.

This script does the necessary configuration in both the local AD and in Azure so once you run it (cleanly) you can move on to FSLogix installation and configuration.

This is intended for use in place of the [AzFilesHybrid Powershell module](https://github.com/Azure-Samples/azure-files-samples/releases) which myself and others have found to be cranky and unreliable.

This script will create a computer object in AD to represent the Kerberos identity for authentication.  The computer object will have the same username as the storage account.

This script is based on earlier work by John Kelbley, a WVD GBB at Microsoft, which parallels the steps under "Option 2" of the [documentation](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-ad-ds-enable#option-2-manually-perform-the-enablement-actions) for enabling ADDS Authentication for Azure Files shares.

The script does do a fair amount of sanity checking to avoid "normal" errors but is not bulletproof.

It is strongly recommended to run the script with the `-Verbose` parameter for more detail on what it is doing.

## Parameters

### storageAccountName

The name of the storage account that holds the Azure Files share.

The name of the storage account must be 15 characters or less to avoid legacy netBIOS issues.

### profileShareName

The name of the Azure Files share that you will use with FSLogix.

If the share does not exist in the specified storage account, it will be created for you.

### ADOuDistinguishedName

The full DN of an OU for the new computer object to be created in.

Example: `OU=WVD,DC=contoso,DC=com`

### ShareAdminGroupName

The name of an AD group that will be granted the "Storage File Data SMB Share Elevated Contributor" IAM role on the Azure Files share.

The membership of this group should be people who will need full access to see the contents of the Profiles share for some reason.

### ShareUserGroupName

The name of an AD group which will be granted the "Storage File Data SMB Share Elevated Contributor" IAM role on the Azure Files share.

This group should contain _all users that will be using the FSLogix profile sharing environment_ (e.g. all WVD users).

### IsGovCloud (ONLY FOR Azure Gov Cloud)

Add this parameter if you are working in Azure Gov Cloud.  This is necessary because the SPN format for the kerberos configuration is different between the public and government clouds.

![Screenshot](https://github.com/hooverken/ARMPowershell/blob/main/Configure-AzFilesForADDSAuthNScreenshot.PNG)

---

# Exterminate-AzureVM.ps1

This script deletes all of the (major) components of a VM:
* Compute instance
* OS disk
* All data disks
* All NICs.

This is intended to make cleanup easier when creating machines for sandboxing etc.  The deletes are NOT UNDOABLE so use with care.