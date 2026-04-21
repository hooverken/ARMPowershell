# Get-AzLogicalToPhysicalAzMappings.ps1
# by Ken Hoover <kenhoo veratmic rosoft dotcom>
# Original version February 2024

# Updated June 2025 to fix token formatting and properly handle the case where a region has no availability zones. KH

# Takes a subscription ID and a region name as parameters and returns the mappings of 
# logical to physical AZ's for that subscription.

# While the mappings are always the same from region to region, some regions don't have AZs so
# The region name is necessary to filter the results correctly.

# Ref: https://learn.microsoft.com/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP

# Output example:

# logicalZone physicalZone
# ----------- ------------
# 1           eastus-az1
# 2           eastus-az3
# 3           eastus-az2

# See README for more information.

#requires -Version 7.0
#requires -Module Az.Accounts

[CmdletBinding()]
param (
    [Parameter(mandatory = $true)][string]$subscriptionId,
    [Parameter(mandatory = $true)][string]$region
)

# This function retrieves the cached access token for the currently-authenticated azure account.
# It is used to authenticate the API call to Azure Resource Manager.
function Get-AzCachedAccessToken()
{
    $ErrorActionPreference = 'Stop'

    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    if(-not $azProfile.Accounts.Count) {
        Write-Error "Not authenticated to Azure.  Use Connect-AzAccount to log in and try again."    
    }
  
    $currentAzureContext = Get-AzContext
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
    $token = $profileClient.AcquireAccessToken($currentAzureContext.Tenant.TenantId)
    return $token.AccessToken
}

# ==================================================================================

# Make sure the user entered a valid location
if ((Get-Azlocation).Location -notcontains $region) {
    Write-Error "Invalid region: $region"
    exit
}

$h = @{}
# $h.Authorization = "Bearer " + ((Get-AzAccessToken).token | ConvertFrom-SecureString)
$h.Authorization = "Bearer " + (Get-AzCachedAccessToken)
$h.'Content-Type' = 'Application/json'

# Query the API to get the list of locations and their availability zone mappings.

$uri = "https://management.azure.com/subscriptions/$subscriptionId/locations?api-version=2022-12-01"
$result = (Invoke-RestMethod -method get -Uri $uri -Headers $h)

$regionResult = $result.value | Where-Object { $_.name -eq $region }

if (!($regionResult.availabilityZoneMappings)) {
    Write-Warning ("No availability zones present in region $region")
    exit
} else {
    $azMappings = $regionResult.availabilityZoneMappings
    $azMappings | ForEach-Object {
        [PSCustomObject]@{
            subscriptionId = $subscriptionId
            logicalZone   = $_.logicalZone
            physicalZone  = $_.physicalZone
        }
    }
}