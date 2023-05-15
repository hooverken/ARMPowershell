# Get-SubscriptionPairAZMappings.ps1

This script compares the availability zone peers of a tarhet subscription as compared to the current subscription.  The output shows which availability zones in the current context matches which availability zones in the target subscription.

My goal is to find a way to quickly identify elements of an application/service with its components split across subscriptions which are (or are not) in the same "actual" Azure AZ.

## Why this matters

In Azure, most regions have multiple availabilty zones at the physical (datacenter) level.  This means that the region, which is made up of multiple datacenters is split into three completely standalone fault domains where each of the three AZ's represents one or more datacenters which share their own power, cooling, network connections, etc.  This helps to ensure that a failure of one of those elements will only impact a specific zone instead of the entire region.  

For example, if I have a pool of 50 VM's that are part of a single application, I would want to split those VM's across three availability zones so that if one zone goes down, the application will still be available in the other two zones.  This is a very common practice for production workloads.

## Why you might need this script

Each Azure subscription has its own logical mapping of availability zone numbers to the underlying physical zones.  This means that what subscription A sees as zone 1 could be the same Azure datacenter as what subscription B sees as zone 2.  If you don't know which zones in subscription A map to which zones in subscription B, you could end up with all of your workload in a single physical zone which would defeat the purpose of using availability zones in the first place.

## What about Proximity Placement Groups?

You may be using [Proximity Placement Groups (PPG's)](https://learn.microsoft.com/en-us/azure/virtual-machines/co-location) to make sure that your Azure resources are located within the same building in the Azure region since this can have significant performance advantages.  This is fine within the context of a single subscription but PPG's are limited to a single subscription in scope so you can't have resources in different subscriptions using the same PPG.
