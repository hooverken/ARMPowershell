# Get-ExpressRouteLocationSpeedOfferings.ps1

This script walks through the list of ExpressRoute providers and locations to see which provider has which port speedss avaialble in which locations.

There are only two speed offerings at this time - 10Gb and 100Gb.

The output is a list of objects with the following properties:

* **Location** *(string)* : The "official" port name for the location, like `Equinix-Paris-PA4`
* **10Gb** *(bool)* : Set to `true` if the location has at least one 10Gb port avaialble for connections, othewrwise set to `false`
* **100Gb** *(bool)* : Set to `true` if the location has at least one 100Gb port avaialble for connections, otherwise set to `false`.

** Example

This screenshot shows how you can filter the output by only returning records where the location name starts with a specific telecom provider.

![Screenshot](https://raw.githubusercontent.com/hooverken/ARMPowershell/main/Configure-AzFilesShareForMSIXAppAttach/Configure-AzFilesShareForMSIXAppAttach.PNG)