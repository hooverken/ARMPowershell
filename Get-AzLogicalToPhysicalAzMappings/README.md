# Get-AzLogicalToPhysicalAzMappings

There are times when deploying a resource into Azure that you need to know which "actual" availability zone that you need to put the resource in.  For example, there are some Azure services that only exist within a single AZ such as AVS.

Because the mappings of "logical" availability zones are randomized for each subscription, you can't simply select zone 1, 2 or 3 when you create the resource because probability says that the resource will be deployed in a different "actual" zone 2 out of 3 times.

This script takes a subscription ID and region name as a parameter and uses [this ARM API call](https://learn.microsoft.com/en-us/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP) to return the mappings of logical to physical availability zones is for that subscription.

Not all AZs are created equal so if you're not sure what zone to use then a Support ticket can get you some guidance on what zone you should be using.

## Example

`.\Get-AzLogicalToPhysicalAzMappings.ps1 -subscriptionId $mySubscriptionId -region eastus`

![Example](https://github.com/hooverken/ARMPowershell/blob/main/Get-AzLogicalToPhysicalAzMappings/example.png?raw=true)