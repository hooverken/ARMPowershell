# Get-AzVmRestrictions.ps1

## Purpose

This powershell script returns information about restrictions on VM SKUs in a specified region, including both region-wide and AZ-specific restrictions.

## About VM Restrictions in Azure

Restrictions are applied at the subscription level to manage availability of VM SKUs in specific regions and availability zones.  These restrictions can vary by subscription and typically include limitations on which regions or zones a particular VM SKU can be deployed to.

>Important:  Zone information returned is always the **logical** zone number for the subscription.  These are mapped internally to the **physical** availability zones available in the region.  To display the logical to physical zone mappings for a subscription you can use the Azure [API call](https://learn.microsoft.com/en-us/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP) or try my [Get-AzLogicalToPhysicalAzMappings](https://github.com/hooverken/ARMPowershell/tree/main/Get-AzLogicalToPhysicalAzMappings) script which retrieves this information directly.

## Parameters

- `-location` (required): A list of one or more regions to check.  Use commas to specify multiple regions like `eastus,centralus`.
- `-sku` (optional): A list of one or more VM skus to check.  If this is not provided then all VM SKUs in the specified location(s) will be returned, like `Standard_D8ls_v5,Standard_E4ds_v5`.

---

## Examples

### Check for restrictions on a specific VM sku in a region

In this example, the listed VM sku is only available in (logical) zone 3 of region `centralus` for the current subscription.

```Powershell
.\Get-AzVmRestrictions.ps1 -location centralus -sku Standard_E4as_v7
```

<img width="752" height="187" alt="singleVmSkuAndRegion" src="https://github.com/user-attachments/assets/ea66fb78-8165-48da-a455-77b6fda75001" />

---

### VM types with multiple restrictions applied

In this example, the VM sku specified has two restriction types applied to it:

- A "Location" restriction which prevents it from being deployed anywhere in the region
- A "Zone" restriction which blocks it from being deployed to the listed zones.  Both of these restrictions need to be lifted to deploy a VM of this type.

```Powershell
.\Get-AzVmRestrictions.ps1 -location centralus -sku Standard_D4as_v5
```
<img width="723" height="378" alt="multipleRestrictionsOnAVm" src="https://github.com/user-attachments/assets/1df060f4-c401-46ea-919e-bf522e5023d9" />

---

### Checking multiple SKUs and regions

This checks both multiple VM types and multiple regions.  This uses the format-table cmdlet to limit the output to just the VM sku name, restriction type and which zones (if any) the VMs are available in.

```powershell
.\Get-AzVmRestrictions.ps1 -location centralus,eastus2 -sku Standard_D4as_v6,Standard_E8as_v7 | ft sku,location,restrictionType,availableZones,notAvailableZones
```
<img width="951" height="268" alt="MultiSkuMultiRegion" src="https://github.com/user-attachments/assets/76f43fac-0727-4edc-b773-34a795b3d928" />

<img width="951" height="268" alt="MultiSkuMultiRegion" src="https://github.com/user-attachments/assets/76f43fac-0727-4edc-b773-34a795b3d928" />

---

### Return all available VM skus in a region with restriction info

In this example, no VM sku is provided so the code returns all available VMs in the region.  This operation returns a large list, only the first few are shown in the screenshot below.

```Powershell
..\Get-AzVmRestrictions.ps1 -location northcentralus | select -first 5 | ft sku,restrictionType,restrictions,availableZones,notAvailableZones
```

<img width="1075" height="255" alt="returnEverything" src="https://github.com/user-attachments/assets/25baf361-153d-42e9-80a3-6cc0463a8be0" />
