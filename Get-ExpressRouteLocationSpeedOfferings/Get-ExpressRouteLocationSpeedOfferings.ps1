<#
.SYNOPSIS
    Lists known ExpressRoute port locations and whether they have 10G, 100G, or both (or neither).

.DESCRIPTION
    This script lists known ExpressRoute port locations and whether they have 10G, 100G, or both (or neither).
    Use this when thinking about setting up ExpressRoute Direct to find out what locations have which
    speeds available.

    Remember, you should pick the CLOSEST LOCATION TO YOUR SITE, **not** the nearest location
    to the Azure region(s) that you will be working with!

.INPUTS
    None. This script does not take any parameters.

.EXAMPLE
    Get-ExpressRouteLocationSpeedOfferings.ps1

.EXAMPLE
    Get-ExpressRouteLocationSpeedOfferings.ps1 | Where-Object { $_.Location.StartsWith('Equinix') } | Format-Table -Auto
#>

# locations which are known to not resolve correctly are in the "bad locations" list.
$badLocations = "CDC-Canberra-CBR20"  # Returns a 429 error for some reason

Get-AzExpressRoutePortsLocation | ForEach-Object { 
    $portLocation = $_.Name
    
    if ($badLocations -Contains $portLocation) { Return } # skip this location if it's on the naughty list

    $portSpeeds = (Get-AzExpressRoutePortsLocation -LocationName $portLocation).AvailableBandwidths

    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "Location" -Value $portLocation

    if ($portSpeeds) {
        $o | Add-Member -MemberType NoteProperty -Name "10Gbps" -Value ($portSpeeds.OfferName.Contains("10 Gbps"))
        $o | Add-Member -MemberType NoteProperty -Name "100Gbps" -Value ($portSpeeds.OfferName.Contains("100 Gbps"))
    }
    else {
        # Port speeds list is empty so nothing available from this provider for this location
        $o | Add-Member -MemberType NoteProperty -Name "10Gbps" -value $false
        $o | Add-Member -MemberType NoteProperty -Name "100Gbps" -value $false
    }
    $o
}