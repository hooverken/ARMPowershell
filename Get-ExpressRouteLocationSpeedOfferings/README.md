# Get-ExpressRouteLocationSpeedOfferings.ps1

This script walks through the list of ExpressRoute providers and locations to see which provider has which port speeds available in which locations.  

There is a lot of demand for ports, especially for 100Gb links.  Port availability can fluctuate from day to day.

There are only two ExpressRoute port speed offerings at this time - 10Gb and 100Gb.

> It's important to understand that the bandwidth of an ExpressRoute circuit is configured **separately** from the link speed of the physical port provided by the ISP.  For example, you can attach using a 10Gb port and have your ExpressRoute circuit bandwidth set to 5Gb.

## Output

The output is a list of objects with the following properties:

* **Location** *(string)* : The "official" port name for the location, like `Equinix-Paris-PA4`
* **10Gbps** *(bool)* : Set to `true` if the location has at least one 10Gb port available for connections, otherwise set to `false`
* **100Gbps** *(bool)* : Set to `true` if the location has at least one 100Gb port available for connections, otherwise set to `false`.

## How to use

Make sure you are authenticated to Azure using `Connect-AzAccount` and just run the script.  I don't believe any special permissions are required.  It doesn't take any parameters at this time because I'm keeping it simple.

The script can take several seconds to complete - be patient.

## Example

This screenshot shows how you can filter the output by only returning records where the location name starts with a specific telecom provider.

![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Get-ExpressRouteLocationSpeedOfferings/Get-ExpressRouteLocationSpeedOfferings.png)