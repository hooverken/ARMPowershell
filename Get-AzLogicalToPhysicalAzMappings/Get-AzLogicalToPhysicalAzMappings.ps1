# Get-AvdHostPoolBilledCharges.ps1
# by Ken Hoover <kenhoo veratmic rosoft dotcom>
# February 2024

# Takes a subscription ID and a region name as parameters and returns the mappings of 
# logical to physical AZ's for that subscriuption in the specified region.

# Ref: https://learn.microsoft.com/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP

# Output example:

# logicalZone physicalZone
# ----------- ------------
# 1           eastus-az1
# 2           eastus-az3
# 3           eastus-az2

# See README for more information.

[CmdletBinding()]
param (
    [Parameter(mandatory = $true)][string]$subscriptionId,
    [Parameter(mandatory = $true)][string]$region
)

# Make sure the user entered a valid location
if ((Get-Azlocation).Location -notcontains $region) {
    Write-Error "Invalid region: $region"
    exit
}

# Headers for the API call.  Make sure you are authenticated to Azure of course.
$h = @{}
$h.Authorization = "Bearer " + (Get-AzAccessToken).token
$h.'Content-Type' = 'Application/json'

$uri = "https://management.azure.com/subscriptions/$subscriptionId/locations?api-version=2022-12-01"

((Invoke-RestMethod -method get -Uri $uri -Headers $h).value | where { $_.name.equals($region)}).availabilityZoneMappings