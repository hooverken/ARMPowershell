# Get-AzVmRestrictions.ps1
# by Ken Hoover <revooh.nek@moc.tfosorcim>
# October 2026

# Returns information about VM SKU restrictions in the specified location, including region-wide and availability zone restrictions.
# NOTE:  This targets the current subscription context, so make sure you have selected the correct subscription before running this script.

[CmdletBinding()]

param (
    [parameter(Mandatory = $false)][string]$sku,
	[parameter(Mandatory = $true)][string]$location
)

$subscriptionID = (Get-AzContext).Subscription.Id

if ($sku) {
    write-verbose ("Filtering VM SKUs for $sku in region $location...")
    $vmSkuList = Get-AzComputeResourceSku -Location $location | Where-Object { ($_.ResourceType -eq 'virtualMachines') -and ($_.Name -eq $sku) }
} else {
    write-verbose ("Retrieving all VM SKUs in region $location...")
    $vmSkuList = Get-AzComputeResourceSku -Location $location | Where-Object { $_.ResourceType -eq 'virtualMachines' }
}

# Check if the region has AZs and, if so, what the AZ numbers are
# This returns a list of zone numbers like (1,2,3)
# This is slow because it checks across all available skus.  Checking a single sku may not return an accurate picture
# since not all VM skus are available in all AZs.
write-verbose ("Checking what zones exist in region $($location)...")
$regionAzList = Get-AzComputeResourceSku -Location $location |
    Where-Object { $_.ResourceType -eq "virtualMachines" } |
    ForEach-Object { $_.LocationInfo.Zones } |
    Sort-Object -Unique

write-verbose ("Available zones in region $($location): $regionAzList")


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
                    Write-verbose ("Restriction zones do not match available AZ zones. Restricted zones: $($restrictedZones), Regional zones: $regionAzList")
                    if ($result.SideIndicator -eq '=>') {
                        Write-Verbose ("VM SKU $($_.Name) is available in zone(s) $($result.InputObject) of region $location")
                        $availableZones = $result.InputObject
                    }
                } else {
                    Write-Verbose ("VM SKU $($_.Name) is not available in any zone of region $location ($($r.ReasonCode))")
                }
            }
            # output an objwect representing the restriction currently being processed. 
            # There may be more than one.
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