param(
	[Parameter(Mandatory = $true)]
	[string]$SubscriptionId,

	[Parameter(Mandatory = $true)]
	[string]$ResourceGroupName,

	[Parameter(Mandatory = $true)]
	[string]$VmName,

	[Parameter(Mandatory = $true)]
	[datetime]$StartTime,

	[Parameter(Mandatory = $true)]
	[datetime]$EndTime,

	[ValidateSet('PT1M','PT5M','PT15M','PT30M','PT1H','P1D')]
	[string]$TimeGrain = 'PT5M'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($StartTime -ge $EndTime) {
	throw "StartTime must be earlier than EndTime."
}

Import-Module Az.Accounts -ErrorAction Stop | Out-Null
Import-Module Az.Compute -ErrorAction Stop | Out-Null
Import-Module Az.Monitor -ErrorAction Stop | Out-Null

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName

if (-not $vm.StorageProfile.DataDisks -or $vm.StorageProfile.DataDisks.Count -eq 0) {
	Write-Output "VM '$VmName' has no data disks."
	return
}

$metricNames = @('Disk Read Operations/Sec', 'Disk Write Operations/Sec')

$matchingDisks = [System.Collections.Generic.List[object]]::new()

foreach ($dataDiskRef in $vm.StorageProfile.DataDisks) {
	if (-not $dataDiskRef.ManagedDisk -or -not $dataDiskRef.ManagedDisk.Id) {
		continue
	}

	$disk = Get-AzDisk -resourceGroupName $ResourceGroupName -DiskName (Split-Path -Leaf $dataDiskRef.ManagedDisk.Id)

	$iopsLimit = [double]$disk.DiskIOPSReadWrite
	if ($iopsLimit -le 0) {
		continue
	}

	$hitPeak = $false

	foreach ($metricName in $metricNames) {
		$metric = Get-AzMetric `
			-ResourceId $disk.Id `
			-MetricName $metricName `
			-TimeGrain (new-timespan -Minutes 5) `
			-StartTime $StartTime `
			-EndTime $EndTime `
			-DetailedOutput

		foreach ($series in $metric.Data) {
			$value = $null
			if ($null -ne $series.Maximum) { $value = [double]$series.Maximum }
			elseif ($null -ne $series.Average) { $value = [double]$series.Average }
			elseif ($null -ne $series.Total) { $value = [double]$series.Total }

			if ($null -ne $value -and $value -ge $iopsLimit) {
				$hitPeak = $true
				break
			}
		}

		if ($hitPeak) { break }
	}

	if ($hitPeak) {
		$matchingDisks.Add($disk) | Out-Null
	}
}

$matchingDisks
