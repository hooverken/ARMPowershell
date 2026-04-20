<#
.SYNOPSIS
    Lists known ExpressRoute port locations and whether they have 10G, 100G, or both (or neither).

.DESCRIPTION
    This script lists known ExpressRoute port locations and whether they have 10G, 100G, or both (or neither).
    Use this when thinking about setting up ExpressRoute Direct to find out what locations have which
    speeds available.

    Remember, you should pick the CLOSEST LOCATION TO YOUR SITE, **not** the nearest location
    to the Azure region(s) that you will be working with!

# CHANGELOG
# - Added MetroOnly parameter to filter output to only include Metro-enabled sites (2 Sep 2025 KH)
# - Improved error handling for bad locations

    Note that this is a partial match, so you can use this to filter on a substring of the location name.

.EXAMPLE
    Get-ExpressRouteLocationSpeedOfferings.ps1

.EXAMPLE
    Get-ExpressRouteLocationSpeedOfferings.ps1 -Verbose

.EXAMPLE
    Get-ExpressRouteLocationSpeedOfferings.ps1 -LocationName 'Equinix' | Format-Table -AutoSize
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$LocationName = ''
)

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][switch]$MetroOnly  # only return locations that have "Metro" in the name
)

# locations which are known to not resolve correctly are in the "bad locations" list.
[Array]$badLocations = @("CDC-Canberra-CBR20")  # Returns a 429 error for some reason

Write-Verbose "Excluding bad locations: $($badLocations -Join ', ')"

Get-AzExpressRoutePortsLocation | `
        Where-Object { $badLocations -NotContains $_.Name } | `
        Where-Object { $_.Name -Like "*$LocationName*" -Or $LocationName.Length -eq 0 } | `
        ForEach-Object { 

Get-AzExpressRoutePortsLocation | ForEach-Object { 

    if ($MetroOnly -and -not ($_.name -like "*Metro*")) { return }  # skip non-Metro locations if MetroOnly is specified

    $portLocation = $_.name
    
        Write-Verbose "Checking available ports for $portLocation..."

        $portSpeeds = (Get-AzExpressRoutePortsLocation -LocationName $portLocation).AvailableBandwidths

        $o = New-Object PSObject
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