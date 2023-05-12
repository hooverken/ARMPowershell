# ARMPowershell

Miscellaneous Powershell scripts for use with Azure ARM

Each folder has a README with details about the script(s) in that folder.

## Contents

| Folder or File Name | Description |
--------------------- | ------------
| **Configure-AzStorageAccountForADDSAuthN.ps1** | Configures an Azure storage account to use [Active Directory (ADDS) authentication](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-active-directory-enable) |
|**Configure-AzFilesShareForFSLogixProfileContainers.ps1** | Sets up a file share on an Azure storage account and configures it for use with [FSlogix profile containers](https://docs.microsoft.com/en-us/azure/virtual-desktop/fslogix-containers-azure-files) |
| **Configure-AzFilesShareForMSIXAppAttach.ps1** | Configures an Azure Files share permissions for use with [MSIX App Attach](https://docs.microsoft.com/en-us/azure/virtual-desktop/what-is-app-attach) and [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) |
| **Configure-AzFilesShareForAzureADAuthentication.ps1** | Configures an Azure storage account for Azure AD authentication. |
| **Get-AvdHostPoolBilledCharges.ps1**| Takes the name of an [Azure Virtual Desktop](https://azure.microsoft.com/en-us/services/virtual-desktop/) host pool as a parameter and returns the actual billed charges for the compute and disk resources for a given time span (default prior 30 days if no start/end date specified). **This has been superseded by [this functionality in Azure Cost Management](https://techcommunity.microsoft.com/t5/azure-virtual-desktop-blog/group-costs-by-host-pool-with-cost-management-now-in-public/ba-p/3638285)** |
| **Get-ExpressRouteLocationSpeedOfferings** | Shows what port speeds (10Gbps or 100GBps) are available from providers in the various [ExpressRoute peering locations](https://learn.microsoft.com/azure/expressroute/expressroute-locations#partners) worldwide.  This is useful when planning ExpressRoute or ExpressRoute Direct connectivity for your org.  In general, you should plan to use the **nearest** location to your on-premises environment to minimize latency and maximize throughput. |
| **Get-VmSkusWithHostBasedEncryptionSupport** | Shows which VM sku offerings support host-based encryption.  In general, this is limited to the newer VM series.|
| **Exterminate-AzureVM.ps1** | Deletes all elements of an Azure VM (compute, OS disk, data disks and NICs) |

All scripts are heavily commented and support the `-Verbose` parameter for a detailed view of their progress during ezxecution.