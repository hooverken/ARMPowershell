# Enable-DiagnosticsForResource.ps1

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)][String]$targetResourceId,
    [Parameter(mandatory=$true)][String]$logAnalyticsWorkspaceResourceId,
    [Parameter(mandatory=$false)][Int32]$retentionInDays = 90  # Default 90 days retention unless otherwise provided
)

# Borrowed from sample code at 
# https://learn.microsoft.com/en-us/powershell/module/az.monitor/new-azdiagnosticsetting?view=azps-10.3.0#example-2-create-diagnostic-setting-for-all-supported-categories

$metric = @() ; $log = @()

# Make sure that this resource is a type that supports flow logs (a NSG or a vnet)
if (!(($targetResourceId.Contains('Microsoft.Network/networkSecurityGroups') -or ($targetResourceId.Contains('Microsoft.Network/virtualNetworks'))))) {
    Write-Error ('Target resource type ' + $targetResourceId.split('/'[6]) + ' does not support flow logs.')
    exit 
}

# Find out what diagnostics cateogires (metrics or otherwise) are available for the target resource ID
$categories = Get-AzDiagnosticSettingCategory -ResourceId $targetResourceId

# Loop through them and build the diagnosticsSettings for the object, either metrics or log settings
$categories | ForEach-Object { 
if ($_.CategoryType -eq "Metrics") {
    $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name -RetentionPolicyEnabled $true
} else{
    $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name -RetentionPolicyEnabled $true
}
}

# Stamp the new diagnostics configuration on the target object.
New-AzDiagnosticSetting -Name 'sendToKentosoHubLAW' -ResourceId $targetResourceId -WorkspaceId $logAnalyticsWorkspaceResourceId -Log $log -Metric $metric

# If this is a NSG or a vnet, enable flow logs too.
if (($targetResourceId.Contains('Microsoft.Network/networkSecurityGroups') -or ($targetResourceId.Contains('Microsoft.Network/virtualNetworks')))) {
    New-AzNetworkWatcherFlowLog -Location eastus `
    -Name pstest `
    -TargetResourceId $targetResourceId `
    -StorageId $storageAccountResourceId `
    -Enabled $true `
    -EnableRetention $true `
    -RetentionPolicyDays $retentionInDays `
    -FormatVersion 2 `
    -EnableTrafficAnalytics `
    -TrafficAnalyticsWorkspaceId $logAnalyticsWorkspaceResourceId
}