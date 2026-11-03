# Get-AzVmRestrictions.ps1
# by Ken Hoover <revooh.nek@moc.tfosorcim>
# October 2026

# Returns information about VM SKU restrictions in the specified location, including region-wide and availability zone restrictions.
# NOTE:  This targets the current subscription context, so make sure you have selected the correct subscription before running this script.

# CHANGELOG:

# 30 Oct 2026 - Initial version
# 03 Nov 2026 - Add support for checking multiple skus and regions (comma-separated lists)

[CmdletBinding()]

param (
    [parameter(Mandatory = $false)][string[]]$sku,  # one or more skus like "Standard_D8as_v7,Standard_D4s_v3"
	[parameter(Mandatory = $true)][string[]]$locations # one or more regions like "eastus,eastus2"
)

$subscriptionID = (Get-AzContext).Subscription.Id

# If the user specified mulitple regions then we need a big outer loop to process them
$locations | % {

    $location = $_

    # Get the full list of VM SKUs available in the specified region
    $allVmSkusInRegion = Get-AzComputeResourceSku -Location $location | Where-Object { $_.ResourceType -eq 'virtualMachines' }

    # Check if the region has AZs and, if so, what the AZ numbers are
    # This returns a list of zone numbers like (1,2,3)
    # This is slow because it checks across all available skus.  Checking a single sku may not return an accurate 
    # picture since not all VM skus are available in all AZs.
    write-verbose ("Checking what zones exist in region $($location)...")
    $regionAzList = $allVmSkusInRegion |
        ForEach-Object { $_.LocationInfo.Zones } |
        Sort-Object -Unique

    # Set up the list if objects to parse based on whether the user specified specific SKUs or wants all of them
    if ($sku) {
        write-verbose ("Filtering VM SKUs for $sku in region $location...")
        # Now filter it down to just the VM skus in the list
        $vmSkuList = $allVmSkusInRegion | Where-Object { $sku -contains $_.Name }
    } else {
        $vmSkuList = $allVmSkusInRegion
    }

    # Go through the list of VM skus and check their restrictions
    $vmSkuList | % {
        $skuRestrictions = $_.Restrictions
        if ($skuRestrictions.count -eq 0) { # no restrictions, yay
            Write-Verbose ("VM SKU $($_.Name) has no restrictions in region $location")
            [PSCustomObject]@{
                subscriptionId = $subscriptionID
                location = $location
                sku = $_.Name
                restrictionType = "None"
                restrictions = "None"
                notAvailableZones = $null
                availableZones = $regionAzList
            }
        } else {
            foreach ($r in $skuRestrictions) {
                # Handle a location/region restriction
                if ($r.Type -eq 'Location') {
                    Write-Verbose ("VM SKU $($_.Name) is restricted region-wide in $location ($($r.ReasonCode))")
                }
                # handle zone restrictions
                if ($r.Type -eq 'Zone') {
                    $restrictedZones = $r.RestrictionInfo.Zones
                    if ($result = Compare-Object $restrictedZones $regionAzList) {
                        Write-verbose ("Only a subset of zones are restricted.  Restricted zones: $($restrictedZones), Regional zones: $regionAzList")
                        if ($result.SideIndicator -eq '=>') {
                            Write-Verbose ("VM SKU $($_.Name) is available in zone(s) $($result.InputObject) of region $location")
                            $availableZones = $result.InputObject
                        }
                    } else {
                        # note in verbose output that all AZs are restricted for this VM sku
                        Write-Verbose ("VM SKU $($_.Name) is not available in any zone of region $location ($($r.ReasonCode))")
                    }
                }
                # output an object representing the restriction currently being processed. 
                # There may be more than one restriction on a sku.
                [PSCustomObject]@{
                    subscriptionId = $subscriptionID
                    location = $location
                    sku = $_.Name
                    restrictionType = $r.Type
                    restrictions = $r.ReasonCode
                    notAvailableZones = $restrictedZones
                    availableZones = $availableZones
                }
            }
        }
    }
}