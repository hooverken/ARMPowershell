# Request-AzComputeQuotaChange.ps1
# By Ken Hoover <revooh.nek@moc.tfosorcim>
# April 2026
# Submits a request to change the quota for a specific VM family in a specific region via the Azure API

# There is no native Powershell cmdlet to do this, though the Azure CLI can do it (az quota create)

# Example:  
#
# Request-AzComputeQuotaChange -vmFamily StandardDSv5Family -region eastus -newCoreLimit 100


[CmdletBinding()]
param (
    [Parameter(mandatory=$true)][String]$vmFamily,
    [Parameter(mandatory=$true)][String]$region,
    [Parameter(mandatory=$true)][int]$newCoreLimit
)

if (-not (Get-Command "Get-AzAccessToken" -ErrorAction SilentlyContinue)) {
    Write-Error "The Az.Accounts module is required to run this script.  Install it using 'Install-Module -Name Az.Accounts' and try again."
    exit
}

# make sure some joker didn't submit a negative number to try to break things
if ($newCoreLimit -le 0) {
    Write-Error "The new core limit must be a positive integer. Please provide a valid value and try again."
    exit
}

# Make sure we have an authenticated session to Azure
if ($null -ne ($context = Get-AzContext)) {
    Write-Verbose "Using subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
} else {
    Write-Error "No Azure context found. Please login using 'Connect-AzAccount' and try again."
    exit
}

# Validate that the region the user specified actually exists.
Write-Verbose ("Validating that the specified region '$region' exists.")
if (-not ((Get-AzLocation -ErrorAction SilentlyContinue).Location -contains $region)) {
    Write-Error "The specified region '$region' is not valid. Please check the available regions and try again."
    exit
}
# validate that the VM family the user specified is available in the requested region
Write-Verbose ("Validating that the requested VM family '$vmFamily' is available in the region '$region'.")
$regionVmTypes = (Get-AzVMUsage -Location $region).Name.Value | where { $_.EndsWith("Family") }
if ($regionVmTypes -notcontains $vmFamily) {
    Write-Error "The specified VM family '$vmFamily' is not available in the region '$region'.`nPlease check the available VM families in that region and try again."
    exit
}

Write-Verbose "Requesting quota change to $newCoreLimit cores for $vmFamily in $region..."

# Build the API request to submit the quota change request
$subscriptionId = $context.Subscription.Id
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token | ConvertFrom-SecureString -AsPlainText

$headers = @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

$location     = $region
$resourceName = $vmFamily
$newLimit     = $newCoreLimit
$apiVersion   = "2020-10-25"

# Example: 'PUT https://management.azure.com/subscriptions/<subscriptionId>/providers/Microsoft.Capacity/resourceProviders/Microsoft.Compute/locations/eastus/serviceLimits/standardFSv2Family?api-version=2020-10-25'

$uri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Capacity/resourceProviders/Microsoft.Compute/locations/$location/serviceLimits/$resourceName"+ "?api-version=$apiversion"

$body = @{
    properties = @{
        name = @{
            value = $resourceName
        }
        limit = $newLimit
        unit  = "Count"
        }
} | ConvertTo-Json -Depth 5

$body

$response = Invoke-RestMethod `
    -Method PUT `
    -Uri $uri `
    -Headers $headers `
    -Body $body `
    -Verbose

$response
