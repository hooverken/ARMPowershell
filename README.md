# ARMPowershell

Miscellaneous Powershell scripts for use with Azure ARM

Each folder has a README with details about the script(s) in that folder.

## Contents

* **Configure-AzStorageAccountForADDSAuthN.ps1** Configures an Azure storage account to use [Active Directory (ADDS) authentication](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable)<br><br>
* **Configure-AzFilesShareForFSLogixProfileContainers.ps1** Sets up a file share on an Azure storage account and configures it for use with [FSlogix profile containers](https://docs.microsoft.com/en-us/azure/virtual-desktop/fslogix-containers-azure-files).<br><br>
* **Configure-AzFilesShareForMSIXAppAttach.ps1** - Configures an Azure Files share permissions for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/)<br><br>
* **Configure-AzFilesShareForAzureADAuthentication.ps1** - Configures an Azure storaage account for Azure AD authentication.  *CURRENTLY BROKEN* <br><br>
* **Get-AvdHostPoolBilledCharges.ps1** - Takes the name of an [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) host pool as a parameter and returns the actual billed charges for the compute and disk resources for a given time span (default prior 30 days if no start/end date specified). **This has been superseded by [this functionality in Azure Cost Management](https://techcommunity.microsoft.com/t5/azure-virtual-desktop-blog/group-costs-by-host-pool-with-cost-management-now-in-public/ba-p/3638285)**<br><br>
* **Exterminate-AzureVM.ps1** - Deletes all elements of an Azure VM (compute, OS disk, data disks and NICs)

All scripts are heavily commented and support the `-Verbose` parameter for a detailed view of their progress during ezxecution.