# Get-ExpressRouteLocationSpeedOfferings.ps1
# by Ken Hoover <k endot hoov er at micr oso ftdotcom>

# Lists known ExpressRoute port locations and whether they have 10G, 100G, or both (or neither)
# Use this when thinking about setting up an ExpressRoute circuit to find out what locations have which
# speeds available.

# Remember, you should pick the CLOSEST LOCATION TO YOUR SITE, **not** the nearest location
# to the Azure region(s) that you will be working with!


#############################################################################

# locations which are known to not resolve correctly are in the "bad locations" list.
$badLocations = "CDC-Canberra-CBR20"  # Returns a 429 error for some reason

Get-AzExpressRoutePortsLocation | ForEach-Object { 
    $portLocation = $_.name
    
    if ($badLocations -contains $portLocation) { return } # skip this location if it's on the naughty list

    $portSpeeds = (Get-AzExpressRoutePortsLocation -LocationName $portLocation).availableBandwidths

    $o = new-object psobject
    $o | add-member -membertype noteproperty -name "Location" -value $portLocation

    if ($portSpeeds) {
        $o | add-member -membertype noteproperty -name "10Gbps" -value ($portSpeeds.offerName.Contains("10 Gbps"))
        $o | add-member -membertype noteproperty -name "100Gbps" -value ($portSpeeds.offerName.Contains("100 Gbps"))
    } else {  # Port speeds list is empty so nothing available from this provider for this location
        $o | add-member -membertype noteproperty -name "10Gbps" -value $false
        $o | add-member -membertype noteproperty -name "100Gbps" -value $false
    }
    $o
}