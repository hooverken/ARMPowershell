# Get-AzLogicalToPhysicalAzMappings

There are times when deploying a resource into Azure that you need to know which "actual" availability zone that you need to put the resource in.  For example, there are some Azure services that only exist within a single AZ such as AVS.

Because the mappings of "logical" availability zones are randomized for each subscription, you can't simply select zone 1, 2 or 3 when you create the resource because probability says that the resource will be deployed in a different "actual" zone 2 out of 3 times.

This script takes a subscription ID and region name as a parameter and returns what the "actual" AZ is that is mapped to the subscription.

Not all AZs are created equal so if you're not sure then a Support ticket can get you some gu8idance on what zone you should be using.

## Example:

`.\Get-AzLogicalToPhysicalAzMappings.ps1 -subscriptionId $mySubscriptionId -region eastus`

![Example](https://github.com/hooverken/ARMPowershell/blob/main/Get-AzLogicalToPhysicalAzMappings/example.png?raw=true)