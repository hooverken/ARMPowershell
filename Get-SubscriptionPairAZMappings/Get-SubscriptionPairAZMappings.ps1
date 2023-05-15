# Get-SubscriptionPairAZMappings.ps1
# by Ken Hoover

# This script compares the availability zone mappings of the target subscription
# to those of the current subscription.

# See the README in this folder to understand why this matters.


[CmdletBinding()]

param (
    [Parameter(mandatory = $true )][string]$targetSubscriptionId
)


###

function Get-AzCachedAccessToken()
{
    $ErrorActionPreference = 'Stop'
  
    if(-not (Get-Module Az.Accounts)) {
        Import-Module Az.Accounts
    }
    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    if(-not $azProfile.Accounts.Count) {
        Write-Error "You must log in to Azure using Connect-AzAccount."
        exit     
    }
  
    $tenant = (Get-AzContext).Tenant.TenantId
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
    Write-Debug ("Getting access token for tenant" + $tenant)
    $token = $profileClient.AcquireAccessToken($tenant)
    $token.AccessToken
}

function Get-AzBearerToken()
{
    $ErrorActionPreference = 'Stop'
    ('Bearer {0}' -f (Get-AzCachedAccessToken))
}

###

$mySubscriptionId = (get-azcontext).Subscription.Id

$subscriptionsList = @("subscriptions/$targetSubscriptionId")

$headers = @{}
$headers.add("Content-Type","application/json")
$headers.add("Authorization",(Get-AzBearerToken))

$body = @{}
$body.Add("location","eastus")
$body.Add("subscriptionIds",$subscriptionsList)

$uri = "https://management.azure.com/subscriptions/$mySubscriptionId/providers/Microsoft.Resources/checkZonePeers/?api-version=2020-01-01"

$result = Invoke-RestMethod -Method POST -uri $uri -Headers $headers -Body ($body | ConvertTo-Json) -ContentType "application/json"

$result.availabilityZonePeers | % { 
    $myAzNumber = $_.availabilityZone
    $otherAzNumber = $_.peers[0].availabilityZone
    write-output "AZ $myAzNumber for subscription $mySubscriptionId is AZ $otherAzNumber for subscription $targetSubscriptionId"
}