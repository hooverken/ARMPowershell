# Get-SubscriptionPairAZMappings.ps1

This script compares the availability zone assignments of a target subscription as compared to the current subscription.  The output shows which availability zone number in the current context matches which availability zone number in the target subscription.

My goal is to find a way to quickly identify elements of an application/service in Azure with its components split across subscriptions which are (or are not) in the same "actual" Azure AZ, such as how the "front end" and "back end" of an application are located.

## Why This Matters

In Azure, most [regions have multiple availabilty zones](https://learn.microsoft.com/azure/reliability/availability-zones-overview) at the physical (datacenter) level.  This means that an Azure region, which is made up of multiple datacenters that work together, is split into separate fault domains -- usually three -- where each of the AZ's represents one or more datacenters which share their own power, cooling, network connections, etc.  This helps to ensure that a failure of one of those services will only impact a specific zone instead of the entire region.

> You can check [this link](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-service-support#azure-regions-with-availability-zone-support) to see which regions worldwide offer availability zones.  In the US, the North Central US, West US and West Central US regions do not currently offer availability zones.

While it's logical to assume that the zone numbers in one subscription will match the zone numbers in another subscription, this is not always the case -- in fact, each Azure _subscription_ has **its own logical mapping** of availability zone numbers to the underlying physical zones. If you don't know which zones in subscription A map to which zones in subscription B, you could inadvertently violate a design goal that you have of making sure that resources in your Azure environment should (or should not) be in the same physical fault domain -- which would defeat the purpose of using availability zones in the first place!

## Wait, What about Proximity Placement Groups?

You may be using [Proximity Placement Groups (PPG's)](https://learn.microsoft.com/azure/virtual-machines/co-location) to make sure that your Azure resources are located within the same _building_ in an Azure region since this can have significant performance advantages.  This is fine within the context of a single subscription but **PPG's are limited to a single subscription in scope** so you can't have resources in different subscriptions using the same PPG.
