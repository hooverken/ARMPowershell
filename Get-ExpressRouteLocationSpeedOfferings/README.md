# Get-ExpressRouteLocationSpeedOfferings.ps1

This script walks through the list of [ExpressRoute connectivity providers](https://learn.microsoft.com/azure/expressroute/expressroute-locations-providers) and locations to see which provider has which port speeds available in which locations.  This is mainly useful when planning an [Expressroute Direct](https://learn.microsoft.com/azure/expressroute/expressroute-erdirect-about) connection.

Each location is served by one or more connectivity providers.  **In general**, you should select an ExpressRoute location which is close to your primary site to minimize latency (and ISP costs) and maximize throughput.

There are two ExpressRoute port speed offerings at this time - 10Gb and 100Gb.

There is high demand for 100Gbps ports, expecially in the continental US.  Port availability fluctuates from day to day as customers claim ports and capacity is added.  If you require a port in a specific location and the desired port speed is not available, open a support ticket for assistance. Microsoft is constantly adding capacity and may be able to help you.

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