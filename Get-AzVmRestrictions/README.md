# Get-AzVmRestrictions.ps1

## Purpose

This powershell script returns information about restrictions on VM SKUs in a specified region, including both region-wide and AZ-specific restrictions.

## Parameters

- `-location` (required): The Azure region to check for VM SKU restrictions.
- `-sku` (optional): The name of the VM SKU to filter for.  If this is not specified, all VM SKUs in the specified location will be returned.

>Important:  Zone information returned is the **logical** zone number for the subscription.
These are mapped internally to the **physical** availability zones available in the region.  To display the logical to physical zone mappings for a subscription you can use the Azure [API call](https://learn.microsoft.com/en-us/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP) or try my [Get-AzLogicalToPhysicalAzMappings](https://github.com/hooverken/ARMPowershell/tree/main/Get-AzLogicalToPhysicalAzMappings) script which retrieves this information directly.

## Examples

### Check for restrictions on a specific VM sku

In this example, the listed VM size (Standard_D8ls_v5) is only available in (logical) zones 1, 3 and 4 of region eastus2 for the subscription.

`.\Get-AzVmRestrictions.ps1 -Location eastus2 -sku Standard_D8ls_v5`

<img width="706" height="192" alt="singleVmSkuRestriction" src="https://github.com/user-attachments/assets/3fc045c7-70f0-4718-b0f8-6136ad15a20a" />


### VM SKUs with Multiple Restrictions On Them

In this example, the VM type specified has two restriction types applied to it:
* A "Location" restriction which prevents it from being deployed anywhere in the region
* A "Zone" restriction which blocks it from being deployed to the listed zones.  Both of these restrictions need to be lifted to deploy a VM of this type.

<img width="602" height="250" alt="twoRestrictionsVm" src="https://github.com/user-attachments/assets/9a678113-0dc2-418b-809f-82e78bed39aa" />

### Check if a set of VM SKUs have restrictions

This is an example of how to check if a list of VM types have restrictions on them.  This uses the format-table cmdlet to limit the output to just the VM sku name, restriction type and which zones (if any) the VMs are available in.

`.\Get-AzVmRestrictions.ps1 -location eastus2 | where { ($_.sku.Equals("Standard_D8lds_v5")) -or ($_.sku.Equals("Standard_E4ds_v5")) -or ($_.sku.Equals("Standard_D2ds_v5")) -or ( $_.sku.Equals("Standard_D4lds_v5")) } | ft sku,restrictionType,availableZones`

<img width="1129" height="206" alt="Screenshot 2026-11-02 123939" src="https://github.com/user-attachments/assets/c5549f9f-9c7b-4c1a-b6ee-34fb8061f388" />

### Return all available VM skus with restriction info

`.\Get-AzVmRestrictions.ps1 -Location eastus2 | where { $_.sku.StartsWith("Standard_D8") }`

In this example, no VM sku is provided so the code returns all available VMs in the region.  A `where` filter is applied to return results which match specific criteria like in this example.  Only the first few objects returned are displayed.

<img width="944" height="491" alt="allVmsWithWhereFilter" src="https://github.com/user-attachments/assets/1ff29f78-6940-4702-b996-1ca52d6a05e2" />
