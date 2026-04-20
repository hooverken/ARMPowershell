<#
.SYNOPSIS
    Creates a metric alert on an Azure Files premium share based on consumed capacity percentage.

.DESCRIPTION
    Monitors the current provisioned size of an Azure Files premium share and creates an alert
    that fires when a specified percentage of capacity has been consumed.

.PARAMETER ResourceGroupName
    The name of the resource group containing the storage account.

.PARAMETER StorageAccountName
    The name of the storage account.

.PARAMETER FileShareName
    The name of the file share to monitor.

.PARAMETER CapacityThresholdPercent
    The percentage of provisioned capacity at which to trigger the alert (e.g., 80).

.PARAMETER ActionGroupId
    The resource ID of the action group for alert notifications.

.EXAMPLE
    Set-AzFileShareCapacityAlert -ResourceGroupName "myRG" -StorageAccountName "mystg" `
        -FileShareName "myshare" -CapacityThresholdPercent 80 -ActionGroupId "/subscriptions/.../myActionGroup"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$FileShareName,

    [Parameter(Mandatory = $true)]
    [int]$CapacityThresholdPercent,

    [Parameter(Mandatory = $true)]
    [string]$ActionGroupId
)

# Get the storage account
$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
if (-not $storageAccount) {
    throw "Storage account '$StorageAccountName' not found in resource group '$ResourceGroupName'"
}

# Get the file share
$fileShare = Get-AzRmStorageShare -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Name $FileShareName
if (-not $fileShare) {
    throw "File share '$FileShareName' not found"
}

# Get provisioned size (in GB for premium shares)
$provisionedSizeGb = $fileShare.QuotaGiB
Write-Host "File share '$FileShareName' provisioned size: $provisionedSizeGb GB"

# Calculate threshold in GB
$thresholdGb = [math]::Round(($provisionedSizeGb * $CapacityThresholdPercent) / 100, 2)
Write-Host "Alert threshold: $thresholdGb GB ($CapacityThresholdPercent%)"

# Create the metric alert
$alertName = "Alert-FileShare-$FileShareName-Capacity-$CapacityThresholdPercent`%"
$alertDescription = "Alert when $FileShareName consumed capacity exceeds $CapacityThresholdPercent% ($thresholdGb GB of $provisionedSizeGb GB)"

$alertParams = @{
    Name                = $alertName
    ResourceGroupName   = $ResourceGroupName
    TargetResourceId    = $storageAccount.Id
    MetricName          = "UsedCapacity"
    Operator            = "GreaterThan"
    Threshold           = $thresholdGb * 1GB
    TimeAggregationId   = "Average"
    WindowSize          = "PT5M"
    Frequency           = "PT1M"
    Description         = $alertDescription
    Severity            = 2
    Action              = New-AzMetricAlertRuleV2Action -ActionGroupId $ActionGroupId
    Dimension           = @(
        @{
            Name     = "FileShareName"
            Operator = "Include"
            Values   = @($FileShareName)
        }
    )
}

Add-AzMetricAlertRuleV2 @alertParams

Write-Host "Alert '$alertName' created successfully"