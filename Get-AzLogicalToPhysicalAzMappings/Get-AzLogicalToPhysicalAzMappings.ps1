[CmdletBinding()]
param (
    [Parameter(mandatory = $true)][string]$subscriptionId,
    [Parameter(mandatory = $true)][string]$region
)

# Make sure the user antered a valid location
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