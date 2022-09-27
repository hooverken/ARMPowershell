# Get-AvdHostPoolBilledCharges.ps1

--- 

*IMPORTANT:  This script has been obsoleted by the release of support for [grouping costs by host pool in Azure Cost Management](https://techcommunity.microsoft.com/t5/azure-virtual-desktop-blog/group-costs-by-host-pool-with-cost-management-now-in-public/ba-p/3638285) in September 2022.  I recommend you use that instead of this code.  I'm going to leave this script here in case it's useful to someone but I am terminating furter development work on this one.*

---

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
![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Get-AvdHostPoolBilledCharges/Get-AvdHostPoolBilledCharges-Output-Screeenshot.png)