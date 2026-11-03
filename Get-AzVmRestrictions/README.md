# Get-AzVmRestrictions.ps1

## Purpose

This powershell script returns information about restrictions on VM SKUs in a specified region, including both region-wide and AZ-specific restrictions.

## Parameters

- `-location` (required): A list of one or more regions to check.  Use commas to specify multiple regions like `eastus,centralus`.
- `-sku` (optional): A list of one or more VM skus to check.  If this is not provided then all VM SKUs in the specified location(s) will be returned.  Use commas to specify multiple skus like `Standard_D8ls_v5,Standard_E4ds_v5`.

>Important:  Zone information returned is the **logical** zone number for the subscription.  These are mapped internally to the **physical** availability zones available in the region.  To display the logical to physical zone mappings for a subscription you can use the Azure [API call](https://learn.microsoft.com/en-us/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP) or try my [Get-AzLogicalToPhysicalAzMappings](https://github.com/hooverken/ARMPowershell/tree/main/Get-AzLogicalToPhysicalAzMappings) script which retrieves this information directly.

---

## Examples

### Check for restrictions on a specific VM sku in one region

In this example, the listed VM sku is only available in (logical) zones 1, 3 and 4 of region eastus2 for the subscription.

```Powershell
.\Get-AzVmRestrictions.ps1 -Location eastus2 -sku Standard_D8ls_v5`
```



---

### VM types with multiple restrictions applied

In this example, the VM sku specified has two restriction types applied to it:

- A "Location" restriction which prevents it from being deployed anywhere in the region
- A "Zone" restriction which blocks it from being deployed to the listed zones.  Both of these restrictions need to be lifted to deploy a VM of this type.

```Powershell
.\Get-AzVmRestrictions.ps1 -location centralus -sku Standard_D4as_v5
```


---

### Checking multiple SKUs and regions

This checks both multiple VM types and multiple regions.  This uses the format-table cmdlet to limit the output to just the VM sku name, restriction type and which zones (if any) the VMs are available in.

```powershell
.\Get-AzVmRestrictions.ps1 -location centralus,eastus2 -sku Standard_D4as_v6,Standard_E8as_v7 | ft sku,location,restrictionType,availableZones,notAvailableZones
```

---

### Return all available VM skus in a region with restriction info

In this example, no VM sku is provided so the code returns all available VMs in the region.  This operation returns a large list, only the first few are shown in the screenshot below.

```Powershell
.\Get-AzVmRestrictions.ps1 -location northcentralus | select -first 5 | ft -auto
```
