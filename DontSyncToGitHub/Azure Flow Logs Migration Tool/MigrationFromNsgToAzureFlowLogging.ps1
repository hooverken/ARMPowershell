#// Copyright (c) Microsoft Corporation.
#// Licensed under the MIT license.

#region Globals

$flowlogCount = @{"count" = 0}
$subscriptionId = ''
$region = ''
$startTime = ''
$reportFileName = 'AnalysisReport.html'
$configPath = '.\RegionSubscriptionConfig.json'
$htmlSartingContent = @"
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Analysis report for nsg to vnet flowlogs</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/js/bootstrap.bundle.min.js"></script>
    <style>
        .table-striped > tbody > tr:nth-child(2n+1) > td, .table-striped > tbody > tr:nth-child(2n+1) > th {
           background-color: #cce6ff;
        }

        .bg-primary
        {
            background-color: #0000ff;
        }

        hr.rounded {
          border-top: 3px solid #0000ff;
          border-radius: 5px;
        }

        html {
            overflow-y: scroll;
            overflow-x: scroll;
        }
    </style>
</head>
<body>
"@

$htmlNavTabContent = @"
<div class='card m-3'>
<ul class="nav nav-pills mb-3 nav-justified" id="pills-tab" role="tablist">
  <li class="nav-item" role="presentation">
    <button class="nav-link active" id="pills-fllist-tab" data-bs-toggle="pill" data-bs-target="#pills-fllist" type="button" role="tab" aria-controls="pills-fllist" aria-selected="true">List of flowlogs</button>
  </li>
  <li class="nav-item" role="presentation">
    <button class="nav-link" id="pills-analysis-tab" data-bs-toggle="pill" data-bs-target="#pills-analysis" type="button" role="tab" aria-controls="pills-analysis" aria-selected="false">Analysis Report</button>
  </li>
  <li class="nav-item" role="presentation">
    <button class="nav-link" id="pills-migration-tab" data-bs-toggle="pill" data-bs-target="#pills-migration" type="button" role="tab" aria-controls="pills-migration" aria-selected="false">Migration</button>
  </li>
  <li class="nav-item" role="presentation">
    <button class="nav-link" id="pills-rollback-tab" data-bs-toggle="pill" data-bs-target="#pills-rollback" type="button" role="tab" aria-controls="pills-rollback" aria-selected="false">Rollback</button>
  </li>
</ul>
<div class="tab-content card" id="pills-tabContent">
"@

$htmlEndingContent = @"
</body>
</html>
"@

$htmlEndingContentWithRollback = @"
<div class='tab-pane fade show active' id='pills-rollback' role='tabpanel' aria-labelledby='pills-rollback-tab'>
<div class="alert alert-info">This tab has logs related to rollback process like which flowlog is being deleted/enabled</div>
<table class='table table-striped table-bordered'>
<colgroup><col/><col/></colgroup>
<thead class='bg-primary text-white text-center'>
</thead>
</table>
</div>
"@

$htmlEndingContentWithMigrationAndRollback = @"
<div class='tab-pane fade show active' id='pills-migration' role='tabpanel' aria-labelledby='pills-migration-tab'>
<div class="alert alert-info">This tab has logs related to migration process, like which flowlog is being created/disabled</div>
<table class='table table-striped table-bordered'>
<colgroup><col/><col/></colgroup>
<thead class='bg-primary text-white text-center'>
</thead>
</table>
</div>
<div class='tab-pane fade show active' id='pills-rollback' role='tabpanel' aria-labelledby='pills-rollback-tab'>
<div class="alert alert-info">This tab has logs related to rollback process, like which flowlog is being deleted/enabled</div>
<table class='table table-striped table-bordered'>
<colgroup><col/><col/></colgroup>
<thead class='bg-primary text-white text-center'>
</thead>
</div>
"@

$htmlTabHeader = @"
<div class='tab-pane fade show active' id='#tabId#' role='tabpanel' aria-labelledby='#tabId#-tab'>
<div class="alert alert-info">#message#</div>
<table class='table table-striped table-bordered'>
<colgroup><col/><col/></colgroup>
<thead class='bg-primary text-white text-center'>
"@

$htmlNewTable = @"
<table class='table table-striped table-bordered'>
<colgroup><col/><col/></colgroup>
<thead class='bg-primary text-white text-center'>
"@

$mutex = $null
$numOfThreads = 16

#endregion

#region Print_Utilities

function Print-FlowLog($fl)
{
    Write-Host "Flowlog settings:"
    Write-Host $fl.Name
    Write-Host $fl.Enabled
    Write-Host $fl.StorageId

    if ($null -ne $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration)
    {
        $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled
        $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.TrafficAnalyticsInterval
        $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceId
        $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceRegion
        $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId
    }
}

function Print-ProcessedFlowlogInfo($flName, $resourceId)
{
    Write-Host "Processing flowlog: " -NoNewLine -ForeGroundColor Blue
    Write-Host $flName -NoNewLine
    Write-Host  " Associated to resource: " -NoNewLine -ForeGroundColor Blue
    Write-Host $resourceId
}

$printProcessedFlowlogInfoStr = ${function:Print-ProcessedFlowlogInfo}.ToString()

function Print-FlowLogs($flList)
{
    [System.Collections.ArrayList]$data = @()

    ($htmlTabHeader.replace("#tabId#", 'pills-fllist')).replace("#message#", "$(Get-Date) This tab has list of flowlogs in given subscription and region") | Out-File $reportFileName -Append

    @"
<tr><th>FlowLogResourceId</th><th>TargetResourceId</th></tr>
</thead>
"@ | Out-File $reportFileName -Append

    $flList | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        [void]($using:mutex).WaitOne()
        $fl = $_

        try
        {
            [void]($using:data).Add([PSCustomObject]@{
                FlowLogResourceId = $fl.Id
                TargetResourceId = $fl.TargetResourceId
            })

            "<tr><td>" + $fl.Id + "</td><td>" + $fl.TargetResourceId + "</td></tr>" | Out-File $using:reportFileName -Append
        }
        finally
        {
            ($using:mutex).ReleaseMutex()
        }
    }

    Get-Job | Wait-Job

    Write-Host ""
    Write-Host "$(Get-Date) List of flowlogs in subscription" $subscriptionId "in region" $region  -ForeGroundColor  Blue
    $data | Format-Table -AutoSize -Wrap

    @"
</table>
</div>
"@ | Out-File $reportFileName -Append
}

#endregion

#region Compare_Utilites

function Compare-Output($createFlowlogTragetList, $disabledFlList, $expectedCreatedFlowLogs, $printLogs)
{
    if ($disabledFlList.Count -ne $expectedDisabledTargetFlMap.Count)
    {
        if ($printLogs)
        {
            Write-Host "Disable list don't match" $disabledFlList.Count $expectedDisabledTargetFlMap.Count -ForeGroundColor Red
        }

        foreach($targetId in $disabledFlList.Keys)
        {
            Write-Host $targetId $disabledFlList[$targetId].Name -ForeGroundColor Red
        }

        return $false
    }

    if ($createFlowlogTragetList.Count -ne $expectedCreatedFlowLogs.Count)
    {
        if ($printLogs)
        {
            Write-Host "created list don't match" $createFlowlogTragetList.Count  $expectedCreatedFlowLogs.Count -ForeGroundColor Red
        }

        return $false
    }

    foreach($targetId in $disabledFlList.Keys)
    {
        if($expectedDisabledTargetFlMap.Contains($targetId) -eq $false -or $expectedDisabledTargetFlMap[$targetId] -ne $disabledFlList[$targetId].Name)
        {
            if ($printLogs)
            {
                Write-host "Not matching flowlog, existing:" $targetId $disabledFlList[$targetId].Name "expected:" $expectedDisabledTargetFlMap[$targetId] -ForeGroundColor Red
            }

            return $false
        }
    }

    foreach($targetId in $createFlowlogTragetList.Keys)
    {
        if($expectedCreatedFlowLogs.ContainsKey($targetId) -eq $false -or $expectedCreatedFlowLogs[$targetId].Contains($createFlowlogTragetList[$targetId].Name) -eq $false)
        {
            if ($printLogs)
            {
                Write-host "Not matching, existing:" $targetId $createFlowlogTragetList[$targetId].Name "expected:" $expectedCreatedFlowLogs[$targetId] -ForeGroundColor Red
            }

            return $false
        }
    }

    return $true
}

function Compare-FlowLogSetting($expected, $found, $printLogs)
{
    if ($expected.Enabled -ne $found.Enabled -or $expected.StorageId -ne $found.StorageId)
    {
        if ($printLogs)
        {
            Write-Host "Either enabled state or storage id is not same for flowlogs" -ForeGroundColor Yellow
        }

        return $false
    }

    if ($expected.RetentionPolicy.Enabled -ne $found.RetentionPolicy.Enabled -or $expected.RetentionPolicy.Days -ne $found.RetentionPolicy.Days)
    {
        if ($printLogs)
        {
            Write-Host "Retention policy is not same for flowlogs" -ForeGroundColor Yellow
        }

        return $false
    }

    if ((-not $expected.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.workspaceId) -and (-not $found.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.workspaceId))
    {
        return $true
    }

    if ((-not $expected.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.workspaceId) -or (-not $found.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.workspaceId))
    {
        if ($printLogs)
        {
            Write-Host "TA config is not same for flowlogs" -ForeGroundColor Yellow
        }

        return $false
    }

    if ($expected.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.enabled -ne $found.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.enabled -or
        $expected.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.workspaceId -ne $found.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.workspaceId -or $expected.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.trafficAnalyticsInterval -ne $found.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.trafficAnalyticsInterval)
    {
        if ($printLogs)
        {
            Write-Host "TA config is not same for flowlogs" -ForeGroundColor Yellow
        }

        return $false
    }

    return $true
}

$compareFlowLogSettingStr = ${function:Compare-FlowLogSetting}.ToString()

function Compare-CreatedFlowLogSettings($expected, $found, $taregtId)
{
    if ($null -eq $found)
    {
        Write-Host "Created resource not found, check if some error during creation" -ForeGroundColor Red
        return $false
    }

    if ($found.ProvisioningState -ne 'Succeeded')
    {
        Write-Host "Unexpected provisioning state:" $found.ProvisioningState -ForeGroundColor Red
        return $false
    }

    if ($found.TargetResourceId -ne $taregtId)
    {
        Write-Host "Incorrect targetId. Expected:" $taregtId "Found:" $found.TargetResourceId -ForeGroundColor Red
        return $false
    }

    $isSettingsSame = Compare-FlowLogSetting $expected $found $false

    if ($isSettingsSame -eq $false)
    {
        Write-Host "Incorrect settings of flowlog" -ForeGroundColor Red
        Print-FlowLog $expected
        Print-FlowLog $found
        return $false
    }

    return $true
}

#endregion

#region Flowlog_CRUD

function Create-FlowLog($targetId, $flSettings, $createdVnetFlowlogs, $targetEtagMap, $mutex, $reportFileName)
{
    $targetResource = Get-AzResource -ResourceId $targetId

    if ($null -eq $targetResource)
    {
        Write-Host "Null target resource"
        return $false
    }

    if ($targetResource.ResourceType -eq 'Microsoft.Network/virtualNetworks/subnets')
    {
        $components = $targetId.Split('/')
        $vnetName = $components[8]
        $flName = $targetResource.Name + '-' + $vnetName + '-' + $targetResource.ResourceGroupName + '-flowlog'
        $flName = $flName.Substring(0, [math]::Min(80, $flName.Length)) #truncating flowlog to size 80 as resources can have name of maximum size 80
    }
    else
    {
        $flName = $targetResource.Name + '-' + $targetResource.ResourceGroupName + '-flowlog'
        $flName = $flName.Substring(0, [math]::Min(80, $flName.Length)) #truncating flowlog to size 80 as resources can have name of maximum size 80
    }

    if (($null -eq $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration) -or (-not $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId))
    {
        Set-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flName -TargetResourceId $targetId -StorageId $flSettings.StorageId -Enabled $flSettings.Enabled -EnableRetention $flSettings.RetentionPolicy.Enabled -RetentionPolicyDays $flSettings.RetentionPolicy.Days -FormatType $flSettings.Format.Type -FormatVersion $flSettings.Format.Version -Force
        Start-Sleep -Seconds 10
        $fl = Get-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flName
        $isExpectedFl = Compare-CreatedFlowLogSettings $flSettings $fl $targetId
        $mutex.WaitOne()

        try
        {
            if ($null -ne $fl)
            {
                [void]$createdVnetFlowlogs.Add($fl)
            }

            if ($isExpectedFl -eq $false)
            {
                Write-Host "Creation of a flowlog" $flName "failed" -ForeGroundColor Red
                Write-Host "Continuing with creation of rest of flowlogs" -ForeGroundColor Blue
                ("<li class='list-group-item list-group-item-danger'>$(Get-Date) Creation of a flowlog" + $flName + "failed</li>") | Out-File $using:reportFileName -Append
                return $false
            }
        }
        finally
        {
            $mutex.ReleaseMutex()
        }
    }
    else
    {
        Set-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flName -TargetResourceId $targetId -StorageId $flSettings.StorageId -Enabled $flSettings.Enabled -EnableRetention $flSettings.RetentionPolicy.Enabled -RetentionPolicyDays $flSettings.RetentionPolicy.Days -FormatType $flSettings.Format.Type -FormatVersion $flSettings.Format.Version -EnableTrafficAnalytics:$flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled -TrafficAnalyticsWorkspaceId $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId -TrafficAnalyticsInterval $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.TrafficAnalyticsInterval -Force
        Start-Sleep -Seconds 10
        $fl = Get-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flName
        $isExpectedFl = Compare-CreatedFlowLogSettings $flSettings $fl $targetId
        $mutex.WaitOne()

        try
        {
            if ($null -ne $fl)
            {
                [void]$createdVnetFlowlogs.Add($fl)
            }

            if ($isExpectedFl -eq $false)
            {
                Write-Host "Creation of a flowlog" $flName "failed" -ForeGroundColor Red
                Write-Host "Continuing with creation of rest of flowlogs" -ForeGroundColor Blue
                ("<li class='list-group-item list-group-item-danger'>$(Get-Date) Creation of a flowlog" + $flName + "failed</li>") | Out-File $using:reportFileName -Append
                return $false
            }
        }
        finally
        {
            $mutex.ReleaseMutex()
        }
    }

    $mutex.WaitOne()

    try
    {
        Write-Host "Created flowlog:" $fl.Name "with target:" $fl.TargetResourceId -ForeGroundColor Green
        ("<li class='list-group-item list-group-item-success'>$(Get-Date) Created flowlog:" + $fl.Name + "with target:" + $fl.TargetResourceId + "</li>") | Out-File $reportFileName -Append
    }
    finally
    {
        $mutex.ReleaseMutex()
    }

    return $true
}

$createFlowLogStr = ${function:Create-FlowLog}.ToString()

function CreateAggregated-Flowlogs($createFlowlogTragetList, $disabledFlList, $createdVnetFlowlogs)
{
    ($htmlTabHeader.replace("#tabId#", 'pills-migration')).replace("#message#", "$(Get-Date) This tab has logs related to migration process, like which flowlog is being created/disabled") | Out-File $reportFileName -Append

    "</table><ul class='list-group'>" | Out-File $reportFileName -Append

    $allSucceeded = @{"success" = $true}

    $createFlowlogTragetList.Keys | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $targetId = $_
        ${function:Create-FlowLog} = $using:createFlowLogStr
        ${function:Compare-CreatedFlowLogSettings} = $using:compareFlowLogSettingStr
        $flSettings = ($using:createFlowlogTragetList)[$targetId]
        ($using:allSucceeded).success = (Create-FlowLog $targetId $flSettings $using:createdVnetFlowlogs @{} $using:mutex $using:reportFileName) -and ($using:allSucceeded).success
    }

    Get-Job | Wait-Job

    $allSucceeded.success = (Disable-FlowLogs $disabledFlList) -and $allSucceeded.success
    "</ul>" | Out-File $reportFileName -Append

    if ($allSucceeded.success)
    {
        Write-Host "$(Get-Date) Migration done successfully" -ForeGroundColor Blue
        "<div class='alert alert-success'>Migration done successfully</div>" | Out-File $reportFileName -Append
    }
    else
    {
        Write-Host "$(Get-Date) There were some errors please go through report" -ForeGroundColor Red
        "<div class='alert alert-danger'>There were some errors in migration please go through report</div>" | Out-File $reportFileName -Append
    }

    "</div>" | Out-File $reportFileName -Append

    return $allSucceeded.success
}

function CreateNonAggregated-Flowlogs($flList, $disabledFlList, $createdVnetFlowlogs, $targetEtagMap)
{
    ($htmlTabHeader.replace("#tabId#", 'pills-migration')).replace('#message#', "$(Get-Date) This tab has logs related to migration process, like which flowlog is being created/disabled") | Out-File $reportFileName -Append
    "</table><ul class='list-group'>" | Out-File $reportFileName -Append

    $allSucceeded = @{ "success" = $true }

    $flList | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $flSettings = $_
        $targetResource = Get-AzResource -ResourceId $flSettings.TargetResourceId -ErrorAction SilentlyContinue
        $numOfThreads = $using:numOfThreads
        $createFlowLogStr = $using:createFlowLogStr
        $compareFlowLogSettingStr = $using:compareFlowLogSettingStr
        $getSubnetIdForNicStr = $using:getSubnetIdForNicStr
        $targetEtagMap = $using:targetEtagMap
        $createdVnetFlowlogs = $using:createdVnetFlowlogs
        $disabledFlList = $using:disabledFlList
        $mutex = $using:mutex
        $allSucceeded = $using:allSucceeded
        $reportFileName = $using:reportFileName

        if ($null -eq $targetResource)
        {
            Write-Host "Target resource" $fl.TargetResourceId "not found for flowlog" $fl.Id -ForeGroundColor Yellow
            return
        }

        #Write-Host "Creating non-aggregated flowlogs for flowLog:" $flSettings.Name "TargetResourceId:" $flSettings.TargetResourceId -ForeGroundColor Blue

        if($targetResource.ResourceType -eq "Microsoft.Network/networkSecurityGroups")
        {
            $nsg = Get-AzNetworkSecurityGroup -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName

            $nsg.Subnets | ForEach-Object -ThrottleLimit $using:numOfThreads -Parallel {
                $subnet = $_
                ${function:Create-FlowLog} = $using:createFlowLogStr
                ${function:Compare-CreatedFlowLogSettings} = $using:compareFlowLogSettingStr
                ${function:Get-SubnetIdForNic} = $using:getSubnetIdForNicStr
                $isTargetPresent = $false
                [void]($using:mutex).WaitOne()

                try
                {
                    $isTargetPresent = ($using:targetEtagMap).ContainsKey($subnet.Id)
                    ($using:targetEtagMap)[$subnet.Id] = $null
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }

                if ($isTargetPresent -eq $false)
                {
                    ($using:allSucceeded).success = (Create-FlowLog $subnet.Id $using:flSettings $using:createdVnetFlowlogs $using:targetEtagMap $using:mutex $using:reportFileName) -and ($using:allSucceeded).success
                }
                else
                {
                    [void]($using:mutex).WaitOne()

                    try
                    {
                        Write-Host "Vnet flowlog already exists for the target" $subnet.Id -ForeGroundColor Green
                        ("<li class='list-group-item list-group-item-success'>$(Get-Date) Vnet flowlog already exists for the target:" + $subnet.Id + "</li>") | Out-File $using:reportFileName -Append
                    }
                    finally
                    {
                        ($using:mutex).ReleaseMutex()
                    }
                }
            }

            $nsg.NetworkInterfaces | ForEach-Object -ThrottleLimit $using:numOfThreads -Parallel {
                $nic = $_
                ${function:Create-FlowLog} = $using:createFlowLogStr
                ${function:Compare-CreatedFlowLogSettings} = $using:compareFlowLogSettingStr
                ${function:Get-SubnetIdForNic} = $using:getSubnetIdForNicStr
                $isTargetPresent = $false
                [void]($using:mutex).WaitOne()

                try
                {
                    $isTargetPresent = ($using:targetEtagMap).ContainsKey($nic.Id)
                    ($using:targetEtagMap)[$nic.Id] = $nic.Id
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }

                if ($isTargetPresent -eq $false)
                {
                    if ($nic.Id.Contains('/virtualMachineScaleSets/'))
                    {
                        $subnetId = Get-SubnetIdForNic($nic.Id);

                        if ($null -eq $subnetId)
                        {
                            [void]($using:mutex).WaitOne()

                            try
                            {
                                Write-Host "Subnet not found for vmss nic hence not creating flowlog" -ForegroundColor Yellow
                                ("<li class='list-group-item list-group-item-info'>$(Get-Date) Subnet not found for vmss nic hence not creating flowlog" + $fl.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
                            }
                            finally
                            {
                                ($using:mutex).ReleaseMutex()
                            }
                        }
                        else
                        {
                            [void]($using:mutex).WaitOne()

                            try
                            {
                                $isTargetPresent = ($using:targetEtagMap).ContainsKey($subnetId)
                                ($using:targetEtagMap)[$subnetId] = $null
                            }
                            finally
                            {
                                ($using:mutex).ReleaseMutex()
                            }

                            if ($isTargetPresent -eq $false)
                            {
                                ($using:allSucceeded).success = (Create-FlowLog $subnetId $using:flSettings $using:createdVnetFlowlogs $using:targetEtagMap $using:mutex $using:reportFileName) -and ($using:allSucceeded).success
                            }
                            else
                            {
                                [void]($using:mutex).WaitOne()

                                try
                                {
                                    Write-Host "Flowlog has already been created on subnet" $subnetId "of vmss nic" $nic.Id -ForeGroundColor Green
                                    ("<li class='list-group-item list-group-item-success'>$(Get-Date) Flowlog has already been created on subnet " + $subnetId + " of vmss nic:" + $nic.Id + "</li>") | Out-File $using:reportFileName -Append
                                }
                                finally
                                {
                                    ($using:mutex).ReleaseMutex()
                                }
                            }
                        }
                    }
                    else
                    {
                        ($using:allSucceeded).success = (Create-FlowLog $nic.Id $using:flSettings $using:createdVnetFlowlogs $using:targetEtagMap $using:mutex $using:reportFileName) -and ($using:allSucceeded).success
                    }
                }
                else
                {
                    [void]($using:mutex).WaitOne()

                    try
                    {
                        Write-Host "Vnet flowlog already exists for the target"  $nic.Id -ForeGroundColor Green
                        ("<li class='list-group-item list-group-item-success'>$(Get-Date) Vnet flowlog already exists for the target:" + $nic.Id + "</li>") | Out-File $using:reportFileName -Append
                    }
                    finally
                    {
                        ($using:mutex).ReleaseMutex()
                    }
                }
            }

            Get-Job | Wait-Job
        }
    }

    Get-Job | Wait-Job
    $allSucceeded.success = (Disable-FlowLogs $disabledFlList) -and $allSucceeded.success
    "</ul>" | Out-File $reportFileName -Append

    if ($allSucceeded.success)
    {
        Write-Host "$(Get-Date) Migration done successfully" -ForeGroundColor Blue
        "<div class='alert alert-success'>Migration done successfully</div>" | Out-File $reportFileName -Append
    }
    else
    {
        Write-Host "$(Get-Date) There were some errors please go through report" -ForeGroundColor Red
        "<div class='alert alert-danger'>There were some errors in migration please go through report</div>" | Out-File $reportFileName -Append
    }

    "</div>" | Out-File $reportFileName -Append

    return $allSucceeded.success
}

function Delete-FlowLogs($flowLogList)
{
    $allSucceeded = @{ "success" = $true }

    $flowLogList | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $fl = $_
        Remove-AzNetworkWatcherFlowLog -ResourceId $fl.Id
        Start-Sleep -Seconds 10
        $deletedFl = Get-AzNetworkWatcherFlowLog -Location $fl.Location -Name $fl.Name -ErrorAction SilentlyContinue
        [void]($using:mutex).WaitOne()

        try
        {
            if ($null -eq $deletedFl)
            {
                Write-Host "Deleted flowlog:" $fl.Name ", TargetResourceId: " $fl.TargetResourceId -ForeGroundColor Green
                ("<li class='list-group-item list-group-item-success'>Deleted flowlog:" + $fl.Name + ", TargetResourceId: " + $fl.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
            }
            else
            {
                $allSucceeded.success = $false
                Write-Host "Failed to delete flowlog:" $fl.Name ", TargetResourceId: " $fl.TargetResourceId -ForeGroundColor Yellow
                ("<li class='list-group-item list-group-item-info'>Failed to delete flowlog:" + $fl.Name + ", TargetResourceId: " + $fl.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
            }
        }
        finally
        {
            ($using:mutex).ReleaseMutex()
        }
    }

    Get-Job | Wait-Job

    return $allSucceeded.success
}

function Disable-FlowLogs($disabledFlList)
{
    $allSucceeded = @{"success" = $true}

    $disabledFlList.Values | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $flSettings = $_
        ${function:Compare-CreatedFlowLogSettings} = $using:compareFlowLogSettingStr

        if ($flSettings.Enabled)
        {
            $flSettings.Enabled = $false

            if (($null -eq $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration) -or (-not $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId))
            {
                Set-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name -TargetResourceId $flSettings.TargetResourceId -StorageId $flSettings.StorageId -Enabled $false -EnableRetention $flSettings.RetentionPolicy.Enabled -RetentionPolicyDays $flSettings.RetentionPolicy.Days -FormatType $flSettings.Format.Type -FormatVersion $flSettings.Format.Version -Force

                Start-Sleep -Seconds 10

                $fl = Get-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name
                $isExpectedFl = Compare-CreatedFlowLogSettings $flSettings $fl $flSettings.TargetResourceId
                ($using:allSucceeded).success = $isExpectedFl -and ($using:allSucceeded).success
                [void]($using:mutex).WaitOne()

                try
                {
                    if ($isExpectedFl -eq $false)
                    {
                        Write-Host "Disablement of a flowlog" $flSettings.Id "failed" -ForeGroundColor Red
                        Write-Host "Continuing disablement of rest of flowlogs" -ForeGroundColor Blue
                        ("<li class='list-group-item list-group-item-danger'>Disablement of a flowlog" + $flSettings.Id + "failed</li>") | Out-File $using:reportFileName -Append
                    }
                    else
                    {
                        Write-Host "Disabled flowlog:" $flSettings.Name "TargetResourceId:" $flSettings.TargetResourceId -ForeGroundColor Green
                        ("<li class='list-group-item list-group-item-success'>Disabled flowlog:" + $flSettings.Name + "TargetResourceId:" + $flSettings.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
                    }
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }
            }
            else
            {
                $isTAEnabled = $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled
                $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled = $false

                Set-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name -TargetResourceId $flSettings.TargetResourceId -StorageId $flSettings.StorageId -Enabled $false -EnableRetention $flSettings.RetentionPolicy.Enabled -RetentionPolicyDays $flSettings.RetentionPolicy.Days -FormatType $flSettings.Format.Type -FormatVersion $flSettings.Format.Version -EnableTrafficAnalytics:$false -TrafficAnalyticsWorkspaceId $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId -TrafficAnalyticsInterval $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.TrafficAnalyticsInterval -Force

                Start-Sleep -Seconds 10

                $fl = Get-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name
                $isExpectedFl = Compare-CreatedFlowLogSettings $flSettings $fl $flSettings.TargetResourceId
                $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled = $isTAEnabled
                ($using:allSucceeded).success = $isExpectedFl -and ($using:allSucceeded).success
                [void]($using:mutex).WaitOne()

                try
                {
                    if ($isExpectedFl -eq $false)
                    {
                        Write-Host "Disablement of a flowlog" $flSettings.Id "failed" -ForeGroundColor Red
                        Write-Host "Continuing disablement of rest of flowlogs" -ForeGroundColor Blue
                        ("<li class='list-group-item list-group-item-danger'>Disablement of a flowlog" + $flSettings.Id + "failed</li>") | Out-File $using:reportFileName -Append
                    }
                    else
                    {
                        Write-Host "Disabled flowlog:" $flSettings.Name "TargetResourceId:" $flSettings.TargetResourceId -ForeGroundColor Green
                        ("<li class='list-group-item list-group-item-success'>Disabled flowlog:" + $flSettings.Name + "TargetResourceId:" + $flSettings.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
                    }
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }
            }
        }
    }

    Get-Job | Wait-Job

    return $allSucceeded.success
}

function Enable-FlowLogs($disabledFlList)
{
    $allSucceeded = @{ "success" = $true }

    $disabledFlList.Values | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $flSettings = $_
        ${function:Compare-CreatedFlowLogSettings} = $using:compareFlowLogSettingStr

        if ($flSettings.Enabled -eq $false)
        {
            $flSettings.Enabled = $true

            if($null -eq $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration)
            {
                Set-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name -TargetResourceId $flSettings.TargetResourceId -StorageId $flSettings.StorageId -Enabled $true -EnableRetention $flSettings.RetentionPolicy.Enabled -RetentionPolicyDays $flSettings.RetentionPolicy.Days -FormatType $flSettings.Format.Type -FormatVersion $flSettings.Format.Version -Force

                Start-Sleep -Seconds 10

                $fl = Get-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name
                $isExpectedFl = Compare-CreatedFlowLogSettings $flSettings $fl $flSettings.TargetResourceId
                ($using:allSucceeded).success = $isExpectedFl -and ($using:allSucceeded).success
                [void]($using:mutex).WaitOne()

                try
                {
                    if ($isExpectedFl -eq $false)
                    {
                        Write-Host "Enablement of a flowlog" $flSettings.Id "failed" -ForeGroundColor Red
                        Write-Host "Continuing with enablement of rest of flowlogs" -ForeGroundColor Blue
                        ("<li class='list-group-item list-group-item-danger'>$(Get-Date) Enablement of a flowlog" + $flSettings.Id + "failed</li>") | Out-File $using:reportFileName -Append
                    }
                    else
                    {
                        Write-Host "Enabled flowlog:" $flSettings.Name "TargetResourceId:" $flSettings.TargetResourceId -ForeGroundColor Yellow
                        ("<li class='list-group-item list-group-item-info'>Enabled flowlog:" + $flSettings.Name + "TargetResourceId:" + $flSettings.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
                    }
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }
            }
            else
            {
                Set-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name -TargetResourceId $flSettings.TargetResourceId -StorageId $flSettings.StorageId -Enabled $true -EnableRetention $flSettings.RetentionPolicy.Enabled -RetentionPolicyDays $flSettings.RetentionPolicy.Days -FormatType $flSettings.Format.Type -FormatVersion $flSettings.Format.Version -EnableTrafficAnalytics:$flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled -TrafficAnalyticsWorkspaceId $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.WorkspaceResourceId -TrafficAnalyticsInterval $flSettings.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.TrafficAnalyticsInterval -Force

                Start-Sleep -Seconds 10

                $fl = Get-AzNetworkWatcherFlowLog -Location $flSettings.Location -Name $flSettings.Name
                $isExpectedFl = Compare-CreatedFlowLogSettings $flSettings $fl $flSettings.TargetResourceId
                ($using:allSucceeded).success = $isExpectedFl -and ($using:allSucceeded).success
                [void]($using:mutex).WaitOne()

                try
                {
                    if ($isExpectedFl -eq $false)
                    {
                        Write-Host "Enablement of a flowlog" $flSettings.Id "failed" -ForeGroundColor Red
                        Write-Host "Continuing with enablement of rest of flowlogs" -ForeGroundColor Blue
                        ("<li class='list-group-item list-group-item-danger'>$(Get-Date) Enablement of a flowlog" + $flSettings.Id + "failed</li>") | Out-File $using:reportFileName -Append
                    }
                    else
                    {
                        Write-Host "Enabled flowlog:" $flSettings.Name "TargetResourceId:" $flSettings.TargetResourceId -ForeGroundColor Yellow
                        ("<li class='list-group-item list-group-item-info'>Enabled flowlog:" + $flSettings.Name + "TargetResourceId:" + $flSettings.TargetResourceId + "</li>") | Out-File $using:reportFileName -Append
                    }
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }
            }
        }
    }

    Get-Job | Wait-Job

    return $allSucceeded.success
}

function Delete-NSGFlowLogs()
{
    Write-Host "Deleting all disabled NSG flowlogs in region:" $region "and subscription:" $subscriptionId -ForegroundColor Blue
    $flList =  Get-AzNetworkWatcherFlowLog -Location $region
    $disabledNSGFlList =  Filter-DisabledNSGFlowLogs $flList
    Write-Host "Following flowlogs will be deleted:" -ForegroundColor Blue
    Print-FlowLogs $disabledNSGFlList
    $proceed = Read-ValuesIgnoringPreviousEntries("Proceed with deletion of flowlogs?(y/n)")

    if ($proceed -eq 'y')
    {
        if ((Delete-FlowLogs $disabledNSGFlList))
        {
            Write-Host "Deleted all disabled NSG flowlogs in region:" $region "and subscription:" $subscriptionId -ForegroundColor Green
        }
        else
        {
            Write-Host "There were some failures in deletion of disabled NSG flowlogs in region:" $region "and subscription:" $subscriptionId ", please take a look" -ForegroundColor Red
        }
    }
}

#endregion

#region Metadata_Formation

function Count-NicsInSubnet($subnet)
{
    $set = New-Object System.Collections.Generic.HashSet[string]

    foreach ($ipconfigs in $subnet.IpConfigurations)
    {
        $position = $ipconfigs.Id.ToLower().IndexOf("/ipconfigurations/")

        if ($position -gt 0 -and $ipconfigs.Id.ToLower().IndexOf('/networkinterfaces/') -gt 0)
        {
            $nicId= $ipconfigs.Id.Substring(0, $position)
            [void]$set.Add($nicId.ToLower())
        }
    }

    return $set.Count
}

$countNicsInSubnetStr = ${function:Count-NicsInSubnet}.ToString()

function Get-SubnetIdForNic($nicId)
{
    $components = $nicId.Split('/')
    $nicRg = $components[4]

    if ($nicId.Contains('/virtualMachineScaleSets/'))
    {
        $vmssName = $components[8]
        $nicName = $components[12]
        $vmss = Get-AzVmss -Name $vmssName -ResourceGroupName $nicRg -ErrorAction SilentlyContinue # check what to do for backload in different subscription vmss scenario

        if ($null -eq $vmss)
        {
            Write-Host "Unable to find vmss for nic ,might be deleted" -ForeGroundColor Yellow
            return
        }

        foreach ($nicIpConfig in $vmss.VirtualMachineProfile.NetworkProfile.networkInterfaceConfigurations)
        {
            if ($vmss.VirtualMachineProfile.NetworkProfile.networkInterfaceConfigurations.Name -eq $nicName)
            {
                return $nicIpConfig.IpConfigurations[0].Subnet.Id
            }
        }

        return $null
    }
    else
    {
        $nicName = $components[8]
        $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $nicRg

        if ($null -eq $nic)
        {
            return $null
        }

        return $nic.IpConfigurations[0].Subnet.Id
    }

    return $null
}

$getSubnetIdForNicStr = ${function:Get-SubnetIdForNic}.ToString()

function Populate-NicInfo($nicId, $processList, $nicFl, $parentMap, $disabledFlList, $nsgNicFlMap)
{
    $components = $nicId.Split('/')
    $subnetId = Get-SubnetIdForNic($nicId)

    if ($null -eq $subnetId)
    {
        Write-Host "Since target reource was not found for flowlog" $nicFl.Id "removing it from processing flowlog list"

        if ($nicFl.TargetResourceId.Contains('/networkSecurityGroups/') -and $nicFl.Enabled)
        {
            $disabledFlList[$nicFl.TargetResourceId] = $nicFl
            Write-Host "Added flowlog to disable list" -ForeGroundColor Yellow
        }

        return
    }

    $components = $subnetId.Split('/')
    $vnetName = $components[8]
    $vnetRg = $components[4]
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRg -ErrorAction SilentlyContinue

    if ($null -eq $vnet)
    {
        Write-Host "Vnet not found for flowlog" $nicFl.Id "removing it from processing flowlog list"
        return
    }

    $parentMap[$subnetId] = $vnet.Id
    $parentMap[$nicId] = $subnetId

    if ($processList.ContainsKey($vnet.Id) -eq $false)
    {
        $processList[$vnet.Id] = @{
            "Vnet" = $vnet
            "Subnets" = @{}
            "VnetFlowLog" = $null
            "AllSubnetsWithSameSetting" = $true
            "SubnetsWithFlCount" = 0
        }
    }

    if ($processList[$vnet.Id]['Subnets'].ContainsKey($subnetId) -eq $false)
    {
        $subnet =  Get-AzVirtualNetworkSubnetConfig -ResourceId $subnetId

        $processList[$vnet.Id]['Subnets'][$subnetId] = @{
            "Subnet" = $subnet
            "NicsInSubnetCount" = Count-NicsInSubnet($subnet)
            "Nics" = @{}
            "SubnetFlowlog" = $null
            "AllNicsWithSameSetting" = $true
        }
    }

    if ($null -eq $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId] -or $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId].TargetResourceId.Contains('Network/networkSecurityGroups/'))
    {
        if ($null -ne $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId])
        {
            if ($processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId].Enabled)
            {
                $disabledFlList[$processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId].TargetResourceId] = $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId]
            }

            $processList[$vnet.Id]['Subnets'][$subnetId]['AllNicsWithSameSetting'] = $true

            foreach ($nicIdInMap in $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'].Keys)
            {
                if ($processList[$vnet.Id]['Subnets'][$subnetId]['AllNicsWithSameSetting'] -eq $false)
                {
                    break
                }

                $nicFlInMap = $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicIdInMap]

                if ($nicIdInMap -ne $nicId -and $null -ne $nicFlInMap)
                {
                    $processList[$vnet.Id]['Subnets'][$subnetId]['AllNicsWithSameSetting'] = Compare-FlowLogSetting $nicFl $nicFlInMap $false
                }
            }

            $nsgNicFlMap.Remove($nicId)
        }

        $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicId] = $nicFl
    }

    if ($processList[$vnet.Id]['Subnets'][$subnetId]['AllNicsWithSameSetting'] -and $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'].Count -gt 1)
    {
        foreach ($nicIdInMap in $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'].Keys)
        {
            $nicFlInMap = $processList[$vnet.Id]['Subnets'][$subnetId]['Nics'][$nicIdInMap]

            if ($nicIdInMap -ne $nicId -and $null -ne $nicFlInMap)
            {
                $processList[$vnet.Id]['Subnets'][$subnetId]['AllNicsWithSameSetting'] = Compare-FlowLogSetting $nicFl $nicFlInMap $false
                break
            }
        }
    }
}

$populateNicInfoStr = ${function:Populate-NicInfo}.ToString()

function Populate-SubnetInfo($subnetId, $processList, $subnetFl, $parentMap, $disabledFlList, $nsgSubnetFlMap)
{
    $components = $subnetId.Split('/')
    $vnetName = $components[8]
    $vnetRg = $components[4]
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRg
    $parentMap[$subnetId] = $vnet.Id

    if ($processList.ContainsKey($vnet.Id) -eq $false)
    {
        $processList[$vnet.Id] = @{
            "Vnet" = $vnet
            "Subnets" = @{}
            "VnetFlowLog" = $null
            "AllSubnetsWithSameSetting" = $true
        }
    }

    if ($processList[$vnet.Id]['Subnets'].ContainsKey($subnetId) -eq $false)
    {
        $subnet =  Get-AzVirtualNetworkSubnetConfig -ResourceId $subnetId

        $processList[$vnet.Id]['Subnets'][$subnetId] = @{
            "Subnet" = $subnet
            "NicsInSubnetCount" = Count-NicsInSubnet($subnet)
            "Nics" = @{}
            "SubnetFlowlog" = $null
            "AllNicsWithSameSetting" = $true
        }
    }

    if ($null -eq $processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog'] -or $processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog'].TargetResourceId.Contains('/Network/networkSecurityGroups/'))
    {
        if ($null -ne $processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog'])
        {
            if ($processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog'].Enabled)
            {
                $disabledFlList[$processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog'].TargetResourceId] = $processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog']
            }

            $processList[$vnet.Id]['AllSubnetsWithSameSetting'] = $true

            foreach ($subnetIdInMap in $processList[$vnet.Id]['Subnets'].Keys)
            {
                $subnetFlInMap = $processList[$vnet.Id]['Subnets'][$subnetIdInMap]['SubnetFlowlog']

                if ($subnetIdInMap -ne $subnetId -and $null -ne $subnetFlInMap)
                {
                    $processList[$vnet.Id]['AllSubnetsWithSameSetting'] = Compare-FlowLogSetting $subnetFl $subnetFlInMap $false
                }

                if ($processList[$vnet.Id]['AllSubnetsWithSameSetting'] -eq $false)
                {
                    break
                }
            }

            $nsgSubnetFlMap.Remove($subnetId)
        }

        $processList[$vnet.Id]['Subnets'][$subnetId]['SubnetFlowlog'] = $subnetFl
    }

    if ($processList[$vnet.Id]['AllSubnetsWithSameSetting'] -and $processList[$vnet.Id]['Subnets'].Count -gt 1)
    {
        foreach ($subnetIdInMap in $processList[$vnet.Id]['Subnets'].Keys)
        {
            $subnetFlInMap = $processList[$vnet.Id]['Subnets'][$subnetIdInMap]['SubnetFlowlog']

            if ($subnetIdInMap -ne $subnetId -and $null -ne $subnetFlInMap)
            {
                $processList[$vnet.Id]['AllSubnetsWithSameSetting'] = Compare-FlowLogSetting $subnetFl $subnetFlInMap $false
                break
            }
        }
    }
}

$populateSubnetInfoStr = ${function:Populate-SubnetInfo}.ToString()

function Populate-VnetInfo($vnetId, $processList, $vnetFl)
{
    $components = $vnetId.Split('/')
    $vnetName = $components[8]
    $vnetRg = $components[4]
    $vnet = $null

    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRg -ErrorAction SilentlyContinue

    if ($null -eq $vnet)
    {
        Write-Host "Since target reource was not found for flowlog" $subnetFl.Id "removing it from processing flowlog list"
        return
    }

    if ($processList.ContainsKey($vnetId) -eq $false)
    {
        $processList[$vnetId] = @{
            "Vnet" = $vnet
            "Subnets" = @{}
            "VnetFlowLog" = $null
            "AllSubnetsWithSameSetting" = $true
        }
    }

    $processList[$vnetId]['VnetFlowLog'] = $vnetFl
}

$populateVnetInfoStr = ${function:Populate-VnetInfo}.ToString()

function Populate-Info($flList, $processList, $nsgNicFlMap, $nsgSubnetFlMap, $parentMap, $disabledFlList, $flIdToEtagTargetIdMap, $targetEtagMap)
{
    Write-Host "$(Get-Date) - Forming metadata to run analysis this might take some time...." -ForeGroundColor Blue

    $flowlogCount.count = 0

    if ($flList.Count -eq 0)
    {
        return
    }

    $flList | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $fl = $_
        ${function:Populate-VnetInfo} = $using:populateVnetInfoStr
        ${function:Populate-SubnetInfo} = $using:populateSubnetInfoStr
        ${function:Populate-NicInfo} = $using:populateNicInfoStr
        ${function:Print-ProcessedFlowlogInfo} = $using:printProcessedFlowlogInfoStr
        ${function:Count-NicsInSubnet} = $using:countNicsInSubnetStr
        ${function:Get-SubnetIdForNic} = $using:getSubnetIdForNicStr
        ${function:Compare-FlowLogSetting} = $using:compareFlowLogSettingStr

        ($using:flIdToEtagTargetIdMap)[$fl.Id] = @($fl.Etag, $fl.TargetResourceId)
        $targetResource = $null

        $targetResource = Get-AzResource -ResourceId $fl.TargetResourceId -ErrorAction SilentlyContinue

        if ($null -eq $targetResource)
        {
            Write-Host "Target resource" $fl.TargetResourceId "not found for flowlog" $fl.Id -ForeGroundColor Yellow
            return
        }

        switch($targetResource.ResourceType)
        {
            "Microsoft.Network/networkSecurityGroups" {
                $nsg = Get-AzNetworkSecurityGroup -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName
                # not synchonizing access to shared maps targetEtagMap, nsgSubnetFlMap, nsgNicFlMap as 1-1 mapping
                ($using:targetEtagMap)[$fl.TargetResourceId] = $nsg.Etag

                if ($nsg.Subnets.Count -eq 0 -and $nsg.NetworkInterfaces.Count -eq 0)
                {
                    Write-Host "No subnet or nic attached to NSG" $targetResource.Id "hence moving it to disbale NSG list"
                    ($using:disabledFlList)[$targetResource.Id] = $fl
                    break
                }

                foreach($subnet in $nsg.Subnets)
                {
                    ($using:nsgSubnetFlMap)[$subnet.Id] = $fl
                    [void]($using:mutex).WaitOne()

                    try
                    {
                        ($using:flowlogCount).count += 1
                        Print-ProcessedFlowlogInfo $fl.Name $subnet.Id
                        Populate-SubnetInfo $subnet.Id $using:processList $fl $using:parentMap $using:disabledFlList $using:nsgSubnetFlMap
                    }
                    finally
                    {
                        ($using:mutex).ReleaseMutex()
                    }
                }

                foreach($nic in $nsg.NetworkInterfaces)
                {
                    ($using:nsgNicFlMap)[$nic.Id] = $fl
                    [void]($using:mutex).WaitOne()

                    try
                    {
                        ($using:flowlogCount).count += 1
                        Print-ProcessedFlowlogInfo $fl.Name $nic.Id
                        Populate-NicInfo $nic.Id $using:processList $fl $using:parentMap $using:disabledFlList
                    }
                    finally
                    {
                        ($using:mutex).ReleaseMutex()
                    }
                }

                break
            }

            "Microsoft.Network/virtualNetworks" {
                $vnet = Get-AzVirtualNetwork -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName
                # not synchonizing access to shared map targetEtagMap as one target can have only one flowlog thus no entry will override other
                ($using:targetEtagMap)[$fl.TargetResourceId] = $vnet.Etag
                [void]($using:mutex).WaitOne()

                try
                {
                    ($using:flowlogCount).count += 1
                    Print-ProcessedFlowlogInfo $fl.Name $targetResource.ResourceId
                    Populate-VnetInfo $targetResource.ResourceId $using:processList $fl
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }

                break
            }

            "Microsoft.Network/virtualNetworks/subnets" {
                $subnet = Get-AzVirtualNetworkSubnetConfig -ResourceId $fl.TargetResourceId
                # not synchonizing access to shared map targetEtagMap as one target can have only one flowlog thus no entry will override other
                ($using:targetEtagMap)[$fl.TargetResourceId] = $subnet.Etag
                [void]($using:mutex).WaitOne()

                try
                {
                    ($using:flowlogCount).count += 1
                    Print-ProcessedFlowlogInfo $fl.Name $targetResource.ResourceId
                    Populate-SubnetInfo $targetResource.ResourceId $using:processList $fl $using:parentMap $using:disabledFlList $using:nsgSubnetFlMap
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }

                break
            }

            "Microsoft.Network/networkInterfaces" {
                $nic = Get-AzNetworkInterface -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName
                # not synchonizing access to shared map targetEtagMap as one target can have only one flowlog thus no entry will override other
                ($using:targetEtagMap)[$fl.TargetResourceId] = $nic.Etag
                [void]($using:mutex).WaitOne()

                try
                {
                    ($using:flowlogCount).count += 1
                    Print-ProcessedFlowlogInfo $fl.Name $targetResource.ResourceId
                    Populate-NicInfo $targetResource.ResourceId $using:processList $fl $using:parentMap $using:disabledFlList $using:nsgNicFlMap
                }
                finally
                {
                    ($using:mutex).ReleaseMutex()
                }

                break
            }

            Default { Write-Host "Invalid target resource type" }
        }
    }

    Get-Job | Wait-Job
    Write-Host "$(Get-Date) - Metadata formation done for" $flowlogCount.count "resources" -ForeGroundColor Blue
}

function Aggregate-FlowLog($processList, $nsgNicFlMap, $nsgSubnetFlMap, $parentMap, $disabledFlList, $createFlowlogTragetList)
{
    Write-Host ""
    Write-Host "Analysis report:" -ForeGroundColor Blue
    Write-Host ""

    ($htmlTabHeader.replace("#tabId#", 'pills-analysis')).replace("#message#", "$(Get-Date) This tab has analysis report for migration like on which targets vnet flowlog will be created and which nsg flowlogs will be disabled") | Out-File $reportFileName -Append

    @"
<tr><th>FlowLog</th><th>TargetNSG</th><th>NSGAssociatedNicOrSubnet</th><th>CanBeAggregated</th><th>AggregatedFlTarget</th><th>Comments</th></tr>
</thead>
"@ | Out-File $reportFileName -Append

    foreach($nicId in $nsgNicFlMap.Keys)
    {
        $nicFl = $nsgNicFlMap[$nicId]
        $subnetId = $null
        $vnetId = $null

        if ($parentMap.ContainsKey($nicId))
        {
            $subnetId = $parentMap[$nicId]
        }

        if ($null -ne $subnetId -and $parentMap.ContainsKey($subnetId))
        {
            $vnetId = $parentMap[$subnetId]
        }

        if ($null -eq $subnetId -or $null -eq $vnetId -or $processList.ContainsKey($vnetId) -eq $false -or $processList[$vnetId]["Subnets"].ContainsKey($subnetId) -eq $false)
        {
            Write-Host "Incomplete metadata hence not processing this nsg flowlog" $nicFl.Id "this is unexpected" -ForegroundColor Magenta
            continue
        }

        $isSubnetFlSameAsNic = Compare-FlowLogSetting $processList[$vnetId]["Subnets"][$subnetId]["SubnetFlowlog"] $nicFl $false

        if ($processList[$vnetId]["Subnets"][$subnetId].AllNicsWithSameSetting -and $processList[$vnetId]["Subnets"][$subnetId]["Nics"].Count -eq $processList[$vnetId]["Subnets"][$subnetId].NicsInSubnetCount -and ($null -eq $processList[$vnetId]["Subnets"][$subnetId]["SubnetFlowlog"] -or $isSubnetFlSameAsNic))
        {
            Write-Host "FlowLog:" $nicFl.Id -ForeGroundColor Green
            Write-Host "TargetNSG:" $nicFl.TargetResourceId -ForeGroundColor Green
            Write-Host "NSG Associated To Nic:" $nicId -ForeGroundColor Green
            Write-Host "Can be aggregated": $true -ForeGroundColor Green
            Write-Host "New target of aggregated flowlog:" $subnetId -ForeGroundColor Green

            ("<tr><td>" + $nicFl.Id + "</td><td>" + $nicFl.TargetResourceId + "</td><td>" + $nicId + "</td><td>" + $true + "</td><td>" + $subnetId + "</td><td></td></tr>") | Out-File $reportFileName -Append

            if ($null -eq $processList[$vnetId]["Subnets"][$subnetId]["SubnetFlowlog"])
            {
                $createFlowlogTragetList[$subnetId] = $nicFl
                $nsgSubnetFlMap[$subnetId] = $nicFl
                Populate-SubnetInfo $subnetId $processList $nicFl $parentMap $disabledFlList $nsgSubnetFlMap
            }
        }
        elseif ($isSubnetFlSameAsNic)
        {
            Write-Host "FlowLog:" $nicFl.Id -ForeGroundColor Green
            Write-Host "TargetNSG:" $nicFl.TargetResourceId -ForeGroundColor Green
            Write-Host "NSG Associated To Nic:" $nicId -ForeGroundColor Green
            Write-Host "Can be aggregated": $true -ForeGroundColor Green
            Write-Host "New target of aggregated flowlog:" $subnetId -ForeGroundColor Green

            ("<tr><td>" + $nicFl.Id + "</td><td>" + $nicFl.TargetResourceId + "</td><td>" + $nicId + "</td><td>" + $true + "</td><td>" + $subnetId + "</td><td></td></tr>") | Out-File $reportFileName -Append
        }
        elseif ($nicId.Contains('/virtualMachineScaleSets/'))
        {
            if ($null -eq $processList[$vnetId]["Subnets"][$subnetId]["SubnetFlowlog"])
            {
                Write-Host "FlowLog:" $nicFl.Id -ForeGroundColor Green
                Write-Host "TargetNSG:" $nicFl.TargetResourceId -ForeGroundColor Green
                Write-Host "NSG Associated To Nic:" $nicId -ForeGroundColor Green
                Write-Host "Can be aggregated": $true -ForeGroundColor Green
                Write-Host "New target of aggregated flowlog:" $subnetId -ForeGroundColor Green
                Write-Host "Comment: Since nsg flowlog is enabled at vmss nic enabling vnet flowlog at subnet" -ForeGroundColor Green

                ("<tr><td>" + $nicFl.Id + "</td><td>" + $nicFl.TargetResourceId + "</td><td>" + $nicId + "</td><td>" + $true + "</td><td>" + $subnetId + "</td><td>Vmss nic has nsg flowlog so enabling vnet flowlog at subnet</td></tr>") | Out-File $reportFileName -Append

                $createFlowlogTragetList[$subnetId] = $nicFl
                $nsgSubnetFlMap[$subnetId] = $nicFl
                Populate-SubnetInfo $subnetId $processList $nicFl $parentMap $disabledFlList $nsgSubnetFlMap
            }
        }
        else
        {
            $createFlowlogTragetList[$nicId] = $nicFl

            if ($processList[$vnetId]["Subnets"][$subnetId].AllNicsWithSameSetting -eq $false)
            {
                Write-Host "FlowLog:" $nicFl.Id -ForeGroundColor Yellow
                Write-Host "TargetNSG:" $nicFl.TargetResourceId -ForeGroundColor Yellow
                Write-Host "NSG Associated To Nic:" $nicId -ForeGroundColor Yellow
                Write-Host "Can be aggregated": $false -ForeGroundColor Yellow
                Write-Host "Comments: Nic flowlog can not be aggregated to subnet flowlog as all nics in subnet do not have flowlog with same settings" -ForeGroundColor Yellow

                ("<tr><td>" + $nicFl.Id + "</td><td>" + $nicFl.TargetResourceId + "</td><td>" + $nicId + "</td><td>" + $false + "</td><td></td><td>Nic flowlog can not be aggregated to subnet flowlog as all nics in subnet do not have flowlog with same settings</td></tr>") | Out-File $reportFileName -Append
            }
            elseif ($processList[$vnetId]["Subnets"][$subnetId]["Nics"].Count -ne $processList[$vnetId]["Subnets"][$subnetId].NicsInSubnetCount)
            {
                Write-Host "FlowLog:" $nicFl.Id -ForeGroundColor Yellow
                Write-Host "TargetNSG:" $nicFl.TargetResourceId -ForeGroundColor Yellow
                Write-Host "NSG Associated To Nic:" $nicId -ForeGroundColor Yellow
                Write-Host "Can be aggregated": $false -ForeGroundColor Yellow
                Write-Host "Comments: Nic flowlog can not be aggregated to subnet flowlog as all nics in subnet do not have flowlog" -ForeGroundColor Yellow

                ("<tr><td>" + $nicFl.Id + "</td><td>" + $nicFl.TargetResourceId + "</td><td>" + $nicId + "</td><td>" + $false + "</td><td></td><td>Nic flowlog can not be aggregated to subnet flowlog as all nics in subnet do not have flowlog</td></tr>") | Out-File $reportFileName -Append
            }
            elseif ($isSubnetFlSameAsNic -eq $false)
            {
                Write-Host "FlowLog:" $nicFl.Id -ForeGroundColor Yellow
                Write-Host "TargetNSG:" $nicFl.TargetResourceId -ForeGroundColor Yellow
                Write-Host "NSG Associated To Nic:" $nicId -ForeGroundColor Yellow
                Write-Host "Can be aggregated": $false -ForeGroundColor Yellow
                Write-Host "Comments: Nic flowlog can not be aggregated to subnet flowlog as subnet already has flowlog with different settings compared to nic flowlogs" -ForeGroundColor Yellow

                ("<tr><td>" + $nicFl.Id + "</td><td>" + $nicFl.TargetResourceId + "</td><td>" + $nicId + "</td><td>" + $false + "</td><td></td><td>Nic flowlog can not be aggregated to subnet flowlog as subnet already has flowlog with different settings compared to nic flowlogs</td></tr>") | Out-File $reportFileName -Append
            }
        }

        if ($nicFl.Enabled)
        {
            $disabledFlList[$nicFl.TargetResourceId] = $nicFl
        }

        Write-Host "---------------------------------------------------------------------------------------"
    }

    foreach($subnetId in $nsgSubnetFlMap.Keys)
    {
        $subnetFl = $nsgSubnetFlMap[$subnetId]
        $vnetId = $null

        if ($parentMap.ContainsKey($subnetId))
        {
            $vnetId = $parentMap[$subnetId]
        }

        if ($null -eq $vnetId -or $processList.ContainsKey($vnetId) -eq $false)
        {
            Write-Host "Incomplete metadata hence not processing this nsg flowlog" $subnetFl.Id "this is unexpected" -ForegroundColor Magenta
            continue
        }

        $isVnetFlSameAsSubnet = Compare-FlowLogSetting $processList[$vnetId]["VnetFlowLog"] $subnetFl $false

        if ($processList[$vnetId].AllSubnetsWithSameSetting -and $processList[$vnetId]["Subnets"].Count -eq $processList[$vnetId]["Vnet"].Subnets.Count -and ($null -eq $processList[$vnetId]["VnetFlowLog"] -or $isVnetFlSameAsSubnet))
        {
            Write-Host "FlowLog:" $subnetFl.Id -ForeGroundColor Green
            Write-Host "TargetNSG:" $subnetFl.TargetResourceId -ForeGroundColor Green
            Write-Host "NSG Associated To Subnet:" $subnetId -ForeGroundColor Green
            Write-Host "Can be aggregated": $true -ForeGroundColor Green
            Write-Host "New target of aggregated flowlog:" $vnetId -ForeGroundColor Green

            ("<tr><td>" + $subnetFl.Id + "</td><td>" + $subnetFl.TargetResourceId + "</td><td>" + $subnetId + "</td><td>" + $true + "</td><td>" + $vnetId + "</td><td></td></tr>") | Out-File $reportFileName -Append

            if ($null -eq $processList[$vnetId]["VnetFlowLog"])
            {
                $createFlowlogTragetList[$vnetId] = $subnetFl
            }

            if ($createFlowlogTragetList.ContainsKey($subnetId))
            {
                $createFlowlogTragetList.Remove($subnetId)
            }
        }
        elseif ($isVnetFlSameAsSubnet)
        {
            Write-Host "FlowLog:" $subnetFl.Id -ForeGroundColor Green
            Write-Host "TargetNSG:" $subnetFl.TargetResourceId -ForeGroundColor Green
            Write-Host "NSG Associated To Subnet:" $subnetId -ForeGroundColor Green
            Write-Host "Can be aggregated": $true -ForeGroundColor Green
            Write-Host "New target of aggregated flowlog:" $vnetId -ForeGroundColor Green

            ("<tr><td>" + $subnetFl.Id + "</td><td>" + $subnetFl.TargetResourceId + "</td><td>" + $subnetId + "</td><td>" + $true + "</td><td>" + $vnetId + "</td><td></td></tr>") | Out-File $reportFileName -Append
        }
        else
        {
            $createFlowlogTragetList[$subnetId] = $subnetFl

            if ($processList[$vnetId].AllSubnetsWithSameSetting -eq $false)
            {
                Write-Host "FlowLog:" $subnetFl.Id -ForeGroundColor Yellow
                Write-Host "TargetNSG:" $subnetFl.TargetResourceId -ForeGroundColor Yellow
                Write-Host "NSG Associated To Subnet:" $subnetId -ForeGroundColor Yellow
                Write-Host "Can be aggregated": $false -ForeGroundColor Yellow
                Write-Host "Comments: Subnet flowlog can not be aggregated to vnet flowlog as all subnets in vnet do not have flowlog with same settings" -ForeGroundColor Yellow

                ("<tr><td>" + $subnetFl.Id + "</td><td>" + $subnetFl.TargetResourceId + "</td><td>" + $subnetId + "</td><td>" + $false + "</td><td></td><td>Subnet flowlog can not be aggregated to vnet flowlog as all subnets in vnet do not have flowlog with same settings</td></tr>") | Out-File $reportFileName -Append
            }
            elseif ($processList[$vnetId]["Subnets"].Count -ne $processList[$vnetId]["Vnet"].Subnets.Count)
            {
                Write-Host "FlowLog:" $subnetFl.Id -ForeGroundColor Yellow
                Write-Host "TargetNSG:" $subnetFl.TargetResourceId -ForeGroundColor Yellow
                Write-Host "NSG Associated To Subnet:" $subnetId -ForeGroundColor Yellow
                Write-Host "Can be aggregated": $false -ForeGroundColor Yellow
                Write-Host "Comments: Subnet flowlog can not be aggregated to vnet flowlog as all subnets in vnet do not have flowlogs" -ForeGroundColor Yellow

                ("<tr><td>" + $subnetFl.Id + "</td><td>" + $subnetFl.TargetResourceId + "</td><td>" + $subnetId + "</td><td>" + $false + "</td><td></td><td>Subnet flowlog can not be aggregated to vnet flowlog as all subnets in vnet do not have flowlogs</td></tr>") | Out-File $reportFileName -Append
            }
            elseif ($isVnetFlSameAsSubnet -eq $false)
            {
                Write-Host "FlowLog:" $subnetFl.Id -ForeGroundColor Yellow
                Write-Host "TargetNSG:" $subnetFl.TargetResourceId -ForeGroundColor Yellow
                Write-Host "NSG Associated To Subnet:" $subnetId -ForeGroundColor Yellow
                Write-Host "Can be aggregated": $false -ForeGroundColor Yellow
                Write-Host "Comments: Subnet flowlog can not be aggregated to vnet flowlog as vnet already has flowlog with different settings when compared to flowlogs on subnets" -ForeGroundColor Yellow

                ("<tr><td>" + $subnetFl.Id + "</td><td>" + $subnetFl.TargetResourceId + "</td><td>" + $subnetId + "</td><td>" + $false + "</td><td></td><td>Subnet flowlog can not be aggregated to vnet flowlog as vnet already has flowlog with different settings when compared to flowlogs on subnets</td></tr>") | Out-File $reportFileName -Append
            }
        }

        if ($subnetFl.Enabled)
        {
            $disabledFlList[$subnetFl.TargetResourceId] = $subnetFl
        }

        Write-Host "---------------------------------------------------------------------------------------"
    }

    "</table>" | Out-File $reportFileName -Append
    Write-Host "List of targets on which flowlog will be enabled with flowlog whose settings will be used:" -ForeGroundColor Blue
    "<h4 class='text-center'>List of targets on which flowlog will be enabled with flowlog whose settings will be used</h4>" | Out-File $reportFileName -Append

    $htmlNewTable | Out-File $reportFileName -Append

    @"
<tr><th>NewTargetResourceId</th><th>FlowLogSettingUsedForCreationOfNewFlowLog</th></tr>
</thead>
"@ | Out-File $reportFileName -Append

    foreach($target in $createFlowlogTragetList.Keys)
    {
        Write-Host $target $createFlowlogTragetList[$target].Name
        ("<tr><td>" + $target + "</td><td>" + $createFlowlogTragetList[$target].Id + "</td></tr>") | Out-File $reportFileName -Append
    }

    Write-Host ""
    Write-Host "List of flowlogs to be disabled:" -ForeGroundColor Blue
    "</table>" | Out-File $reportFileName -Append
    "<h4 class='text-center'>List of flowlogs to be disabled</h4>" | Out-File $reportFileName -Append
    $htmlNewTable | Out-File $reportFileName -Append

    @"
<tr><th>FlowLogsToBeDisabled</th><th>TargetResourceId</th></tr>
</thead>
"@ | Out-File $reportFileName -Append

    foreach($fl in $disabledFlList.Values)
    {
        Write-Host $fl.Name
        ("<tr><td>" + $fl.Id + "</td><td>" + $fl.TargetResourceId + "</td></tr>") | Out-File $reportFileName -Append
    }

    Write-Host ""
        @"
</table>
</div>
"@ | Out-File $reportFileName -Append
}


#endregion

#region Others

function Filter-DisabledNSGFlowLogs($flList)
{
	[System.Collections.ArrayList]$disabledNSGFlList = @()

	foreach ($fl in $flList)
	{
		if ($fl.Enabled)
		{
			continue
		}

		$targetResource = Get-AzResource -ResourceId $fl.TargetResourceId

		if ($null -ne $targetResource -and $targetResource.ResourceType -eq "Microsoft.Network/networkSecurityGroups")
		{
			[void]$disabledNSGFlList.Add($fl)
		}
	}

	return $disabledNSGFlList
}

function Read-ValuesIgnoringPreviousEntries($readMsg)
{
    while ($true)
    {
        $res = Read-Host $readMsg

        if ($res -ne '')
        {
            return $res
        }
    }

    return ""
}

function Get-EtagForTargetResource($targetResourceId)
{
    $targetResource = Get-AzResource -ResourceId $targetResourceId

    switch($targetResource.ResourceType)
    {
        "Microsoft.Network/networkSecurityGroups" {
            $nsg = Get-AzNetworkSecurityGroup -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName
            return $nsg.Etag
        }

        "Microsoft.Network/virtualNetworks" {
            $vnet = Get-AzVirtualNetwork -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName
            return $vnet.Etag
        }

        "Microsoft.Network/virtualNetworks/subnets" {
            $subnet = Get-AzVirtualNetworkSubnetConfig -ResourceId $fl.TargetResourceId
            return $subnet.Etag
        }

        "Microsoft.Network/networkInterfaces" {
            $nic = Get-AzNetworkInterface -Name $targetResource.Name -ResourceGroup $targetResource.ResourceGroupName
            return $nic.Etag
        }
        Default { Write-Host "Invalid target resource type" }
    }
}

$getEtagForTargetResourceStr = ${function:Get-EtagForTargetResource}.ToString()

function Check-ReRunOfAnalysisRequired($flIdToEtagTargetIdMap, $targetEtagMap)
{
    Write-Host "$(Get-Date) Checking if re-running analysis is required" -ForeGroundColor Blue
    $latestFlList = Get-AzNetworkWatcherFlowLog -Location $region

    if ($flIdToEtagTargetIdMap.Count -ne $latestFlList.Count)
    {
        Write-Host "There is change in topology since last time you ran the analysis so re-running analysis stage" -ForeGroundColor Magenta
        return $true
    }

    $hasTopoChanged = @{ "isChanged" = $false }

    $latestFlList | ForEach-Object -ThrottleLimit $numOfThreads -Parallel {
        $fl = $_
        ${function:Get-EtagForTargetResource} = $using:getEtagForTargetResourceStr

        if (($using:hasTopoChanged).isChanged -eq $false -and ($using:flIdToEtagTargetIdMap).ContainsKey($fl.Id) -eq $false -or ($using:flIdToEtagTargetIdMap)[$fl.Id][0] -ne $fl.Etag -or ($using:flIdToEtagTargetIdMap)[$fl.Id][1] -ne $fl.TargetResourceId -or ($using:targetEtagMap).ContainsKey($fl.TargetResourceId) -eq $false -or ($using:targetEtagMap)[$fl.TargetResourceId] -ne (Get-EtagForTargetResource $fl.TargetResourceId))
        {
            ($using:hasTopoChanged).isChanged = $true
        }
    }

    Get-Job | Wait-Job

    if ($hasTopoChanged.isChanged)
    {
        Write-Host "There is change in topology since last time you ran the analysis so re-running analysis stage" -ForeGroundColor Magenta
    }

    return $hasTopoChanged.isChanged
}

#endregion

#region Driver

function Run-Analysis()
{
    $processList = @{}
    $nsgNicFlMap = @{}
    $nsgSubnetFlMap = @{}
    $parentMap = @{}
    $createFlowlogTragetList = @{}
    $disabledFlList = @{}
    $flIdToEtagTargetIdMap = @{}
    $targetEtagMap = @{}
    [System.Collections.ArrayList]$createdVnetFlowlogs = @()

    # create the report file in html format
    $culture = [System.Globalization.CultureInfo]::CreateSpecificCulture('en-US')
    $startTime = (Get-Date).ToString('ddMMyyyyh.mm.ss.tt', $culture)
    $reportFileName = 'AnalysisReport-' + $subscriptionId + "-" + $region + "-" + $startTime + '.html'
    Write-Host ('After the end of the process you can find the report in file ' + $reportFileName) -ForeGroundColor Blue
    $htmlSartingContent | Out-File $reportFileName
    ("<h3 class='text-primary text-center mb-5'>Migration report for subscription: " + $subscriptionId + " and region: " + $region + "</h2>") | Out-File $reportFileName -Append
    $htmlNavTabContent | Out-File $reportFileName -Append

    Write-Host "Start time: $(Get-Date)" -ForeGroundColor Blue
    Write-Host "Finding all flowlogs for the given subscription in region" $region  -ForeGroundColor  Blue
    $flList =  Get-AzNetworkWatcherFlowLog -Location $region
    Print-FlowLogs $flList
    Populate-Info $flList $processList $nsgNicFlMap $nsgSubnetFlMap $parentMap $disabledFlList $flIdToEtagTargetIdMap $targetEtagMap
    Aggregate-FlowLog $processList $nsgNicFlMap $nsgSubnetFlMap $parentMap $disabledFlList $createFlowlogTragetList

    Write-Host "In aggregation mode migration (recommended)" $createFlowlogTragetList.Count "vnet flowlog will be created" -ForeGroundColor Magenta
    Write-Host "In non-aggregation mode migration" $flowlogCount.count "vnet flowlog will be created" -ForeGroundColor Magenta
    Write-Host "Number of NGS flowlogs to be disabled:" $disabledFlList.count -ForeGroundColor Magenta
    Write-Host "You can view the above info in html file" $reportFileName "located in the same folder as script"

    $perms = Read-ValuesIgnoringPreviousEntries(@"
Select:
1. Re-Run analysis
2. Proceed with migration with aggregation
3. Proceed with migration without aggregation
4. Quit

"@)

    switch($perms)
    {
        "1" {
            Write-Host "Re-running analysis" -ForeGroundColor Blue
            $htmlEndingContentWithMigrationAndRollback | Out-File $reportFileName -Append
            "</div>" | Out-File $reportFileName -Append
            $htmlEndingContent | Out-File $reportFileName -Append
            Run-Analysis
            return
        }

        "2" {
            $isAnalysiRerunReq = Check-ReRunOfAnalysisRequired $flIdToEtagTargetIdMap $targetEtagMap

            if ($isAnalysiRerunReq)
            {
                $htmlEndingContentWithMigrationAndRollback | Out-File $reportFileName -Append
                "</div>" | Out-File $reportFileName -Append
                $htmlEndingContent | Out-File $reportFileName -Append
                Run-Analysis
                return
            }
            else
            {
                Write-Host "$(Get-Date) Migration started" -ForeGroundColor Blue
                CreateAggregated-Flowlogs $createFlowlogTragetList $disabledFlList $createdVnetFlowlogs
            }

            break
        }

        "3" {
            $isAnalysiRerunReq = Check-ReRunOfAnalysisRequired $flIdToEtagTargetIdMap $targetEtagMap

            if ($isAnalysiRerunReq)
            {
                $htmlEndingContentWithMigrationAndRollback | Out-File $reportFileName -Append
                "</div>" | Out-File $reportFileName -Append
                $htmlEndingContent | Out-File $reportFileName -Append
                Run-Analysis
                return
            }
            else
            {
                Write-Host "$(Get-Date) Migration started" -ForeGroundColor Blue
                CreateNonAggregated-Flowlogs $flList $disabledFlList $createdVnetFlowlogs $targetEtagMap
            }

            break
        }

        "4" {
            Write-Host "$(Get-Date) Quitting" -ForeGroundColor Green
            $htmlEndingContentWithMigrationAndRollback | Out-File $reportFileName -Append
            "</div>" | Out-File $reportFileName -Append
            $htmlEndingContent | Out-File $reportFileName -Append
            Write-Host "You can view the above info in html file" $reportFileName "located in the same folder as script" -ForegroundColor Blue

            return
        }
        Default {
            Write-Host "Invalid selection"
            "</div>" | Out-File $reportFileName -Append
            $htmlEndingContent | Out-File $reportFileName -Append
            return
        }
    }

    $rollback = Read-ValuesIgnoringPreviousEntries("Do you want to rollback? You won't get the option to revert the actions done now again.(y/n)")

    ($htmlTabHeader.replace("#tabId#", 'pills-rollback')).replace('#message#', "$(Get-Date) This tab has logs related to rollback process, like which flowlog is being deleted/enabled") | Out-File $reportFileName -Append

    if ($rollback -eq 'y')
    {
        Write-Host "$(Get-Date) Rollback started" -ForeGroundColor Blue
        "</table><ul class='list-group'>" | Out-File $reportFileName -Append
        $enabledFlowLogs = Enable-FlowLogs $disabledFlList
        $deleteCreateFlowLogs = Delete-Flowlogs $createdVnetFlowlogs
        "</ul>" | Out-File $reportFileName -Append

        if ($enabledFlowLogs -and $deleteCreateFlowLogs)
        {
            Write-Host "$(Get-Date) Rollback done successfully" -ForeGroundColor Green
            "<div class='alert alert-success'>Rollback done successfully</div>" | Out-File $reportFileName -Append
        }
        else
        {
            Write-Host "$(Get-Date) There were some errors in rollback please go through report" -ForeGroundColor Red
            "<div class='alert alert-danger'>There were some errors in rollback please go through report</div>" | Out-File $reportFileName -Append
        }

        "</div>" | Out-File $reportFileName -Append
    }
    else
    {
        "</table>" | Out-File $reportFileName -Append
        "</div>" | Out-File $reportFileName -Append
        $htmlEndingContentWithRollback | Out-File $reportFileName -Append
    }

    $htmlEndingContent | Out-File $reportFileName -Append
    Write-Host "You can view the above info in html file" $reportFileName "located in the same folder as script"
    Write-Host "End time: $(Get-Date)" -ForeGroundColor Blue
}

$perms = Read-ValuesIgnoringPreviousEntries(@"
Select one of the following options for flowlog migration:
1. Run analysis
2. Delete NSG flowlogs
3. Quit

"@)

if ($perms -eq '1' -or $perms -eq '2')
{

    try
    {
        $configPath = Read-ValuesIgnoringPreviousEntries("Please enter the path to scope selecting config file:")
        $numOfThreadsStr = Read-Host("Please enter the number of threads you would like to use, press enter for using default value of 16:")

        if ($numOfThreadsStr -eq '')
        {
            $numOfThreads = 16
        }
        else
        {
            $numOfThreads = [int]$numOfThreadsStr
        }

        if ($numOfThreads -le 0)
        {
            Write-Host "Number of threads can't be negative or zero, quitting!" -ForeGroundColor Red
            return
        }

        Write-Host "Using" $numOfThreads " number of threads"
        $subIdRegion = Get-Content -Path $configPath | ConvertFrom-Json  -AsHashtable -ErrorAction SilentlyContinue
    }
    catch
    {
        Write-Host "Config file in incorrect json format please format it correctly" -ForegroundColor Red
        return
    }

    if ($null -eq $subIdRegion)
    {
        Write-Host "Config file in incorrect json format please format it correctly" -ForegroundColor Red
        return
    }

    Connect-AzAccount
    $mutex = New-Object Threading.Mutex($false, "MyMutex")

    foreach($subId in $subIdRegion.Keys)
    {
        $subscriptionId = $subId

        foreach($reg in $subIdRegion[$subId])
        {
            $region = $reg
            Set-AzContext -SubscriptionId $subscriptionId

            if ($perms -eq '1')
            {
                Run-Analysis
            }
            else
            {
                Delete-NSGFlowLogs
            }
        }
    }

    $mutex.Close()
}
else
{
    Write-Host "$(Get-Date) Quitting" -ForeGroundColor Green
}

#endregion
