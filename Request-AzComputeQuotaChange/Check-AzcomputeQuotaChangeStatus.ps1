# Check-AzComputeQuotaChangeStatus.ps1
# By Ken Hoover <revooh.nek@moc.tfosorcim>
# April 2026
# Checks the status of a quota change requests in a given region via the Azure API

# There is no native Powershell cmdlet to do this, though the Azure CLI can do it (az quota show)

# Example:  
#
# Check-AzComputeQuotaChangeStatus -vmFamily StandardDSv5Family -region eastus -newCoreLimit 100

<#
.SYNOPSIS
    Returns the status of quota change requests in a given region via the Azure API
.DESCRIPTION
    This function checks the status of open quota change requests in a specific region via the Azure API. 
    It requires the Az.Accounts module and an authenticated Azure session.
.NOTES
    This function is not supported in Linux.
.LINK
    https://learn.microsoft.com/en-us/rest/api/reserved-vm-instances/quota?view=rest-reserved-vm-instances-2022-11-01
.EXAMPLE
    Check-AzComputeQuotaChangeStatus -vmFamily StandardDSv5Family -region eastus -newCoreLimit 100

.PARAMETER location
    The Azure region to check for quota change request status. This should be the same region used when submitting the quota change request.
#>


[CmdletBinding()]
param (
    [Parameter(mandatory=$true)][String]$location
)


if (-not (Get-Command "Get-AzAccessToken" -ErrorAction SilentlyContinue)) {
    Write-Error "The Az.Accounts module is required to run this script.  Install it using 'Install-Module -Name Az.Accounts' and try again."
    exit
}

# Make sure we have an authenticated session to Azure
if ($null -ne ($context = Get-AzContext)) {
    Write-Verbose "Using subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    $subscriptionId = $context.Subscription.Id
} else {
    Write-Error "No Azure context found. Please login using 'Connect-AzAccount' and try again."
    exit
}

Write-Verbose "Checking status of quota change status requests in $location for subscription $($context.Subscription.Name)..."

# Validate that the region the user specified actually exists.
Write-Verbose ("Validating that the specified region '$location' exists.")
if (-not ((Get-AzLocation -ErrorAction SilentlyContinue).Location -contains $location)) {
    Write-Error "The specified region '$location' is not valid. Please check the available regions and try again."
    exit
}

# Build the API request to check the quota change status
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token | ConvertFrom-SecureString -AsPlainText

$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

$apiVersion   = "2020-10-25"

# Example: GET https://management.azure.com/subscriptions/<subscriptionId>/providers/Microsoft.Capacity/resourceProviders/Microsoft.Compute/locations/eastus/serviceLimitsRequests?api-version=2020-10-25


$uri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Capacity/resourceProviders/Microsoft.Compute/locations/$location/serviceLimitsRequests"+ "?api-version=$apiversion"

$response = Invoke-RestMethod `
    -Method GET `
    -Uri $uri `
    -Headers $headers `
    -Body $body

Write-Verbose ("Request status summary:")
write-Verbose ("`t* Requested " + $response.value.properties.value.limit + " cores in $location of type " + $response.value.properties.value.name.value)
Write-Verbose ("`t* Request ID: " + $response.value.id)
Write-Verbose ("`t* Submitted: " + $response.value.properties.requestSubmitTime)
Write-Verbose ("`t* Provisioning State: " + $response.value.properties.provisioningState)
Write-Verbose ("`t* Message: " + $response.value.properties.value.message)
Write-Verbose ("`t* Action: " + $response.value.properties.value.action)

$outlist = @()
$response.value.properties | % {
    $o = New-Object PSObject -Property @{
        submitTime = $_.requestSubmitTime
        vmFamily = $_.value.name.value
        quantity = $_.value.limit
        provisioningState = $_.value.provisioningState
        message = $_.value.message
    }
    $outlist += $o
}

$outlist # | ft submitTime, provisioningState, vmFamily, quantity, message