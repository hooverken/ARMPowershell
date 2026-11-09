#

[CmdletBinding()]

param(
	[Parameter(Mandatory = $true)][string]$ResourceGroupName,
	[Parameter(Mandatory = $true)][ValidateSet('1', '2', '3')][string]$Zone,
	[string]$SubscriptionId
)

## functions
function New-ZonalCapacityReservationGroup {
	param(
        [Parameter(Mandatory = $true)][string]$CRGResourceGroupName,
		[Parameter(Mandatory = $true)][string]$Region,
        [Parameter(Mandatory = $true)][ValidateSet('1', '2', '3')][string]$AvailabilityZone
    )

	$crgName = "CRG-Zone" + $AvailabilityZone + "-" + $Region.ToLowerInvariant()
	$crgName = $crgName -replace '[^a-z0-9\-]', '-'

	$existingCrg = Get-AzCapacityReservationGroup -ResourceGroupName $CRGResourceGroupName -Name $crgName -ErrorAction SilentlyContinue
	if ($existingCrg) {
		Write-Output "Capacity Reservation Group '$crgName' already exists."
		return $existingCrg
	}

	$newCrg = New-AzCapacityReservationGroup `
		-ResourceGroupName $CRGResourceGroupName `
		-Name $crgName `
		-Location $Region `
		-Zone $Zone

	Write-Output "Created Capacity Reservation Group '$crgName' in region '$Region' for SKU '$VmSku'."
	return $newCrg
}

function New-CapacityReservationForSku {
	param(
		[Parameter(Mandatory = $true)][string]$crgName,
        [Parameter(Mandatory = $true)][string]$crgResourceGroupName,
		[Parameter(Mandatory = $true)][string]$VmSku,
		[Parameter(Mandatory = $true)][ValidateSet('1', '2', '3')][string]$AvailabilityZone
	)

	$reservationName = ($VmSku.ToLowerInvariant() + '-' + $AvailabilityZone)

	$location = (get-azresourcegroup -name $crgResourceGroupName -ErrorAction Stop).Location

	$existingReservation = Get-AzCapacityReservation `
		-ResourceGroupName $crgResourceGroupName `
		-CapacityReservationGroupName $crgName `
		-Name $reservationName `
		-ErrorAction SilentlyContinue

	if ($existingReservation) {
		Write-Output "Capacity Reservation '$reservationName' already exists in group '$crgName'."
		return $existingReservation
	}

	$newReservation = New-AzCapacityReservation `
		-ResourceGroupName $crgResourceGroupName `
		-CapacityReservationGroupName $crgName `
		-Name $reservationName `
		-location $location `
		-Sku $VmSku `
		-Zone $AvailabilityZone `
		-CapacityToReserve 0

	Write-Output "Created Capacity Reservation '$reservationName' in group '$crgName' for SKU '$VmSku' in zone '$AvailabilityZone'."
	return $newReservation
}

function increment-parkingSpacesForExistingReservation {

	[Parameter(Mandatory = $true)][string]$crgName,
	[Parameter(Mandatory = $true)][string]$crgResourceGroupName,
	[Parameter(Mandatory = $true)][string]$VmSku,
	[Parameter(Mandatory = $true)][ValidateSet('1', '2', '3')][string]$AvailabilityZone

	$crg = get-azcapacityreservationgroup -ResourceGroupName $crgResourceGroupName -Name $crgName -ErrorAction Stop
	$reservation = get-azcapacityreservation -ResourceGroupName $crg.ResourceGroupName -CapacityReservationGroupName $crgName -Name $reservationName -ErrorAction Stop

	if ($reservation.CapacityToReserve -eq $reservation.AllocatedCapacity) {
		Write-Output "Current capacity for reservation '$($reservation.Name)' is fully allocated. Incrementing reserved capacity by 1 to create parking space."
		$reservation.CapacityToReserve += 1
		Set-AzCapacityReservation -InputObject $reservation | Out-Null
	} else {
		Write-Output "Current capacity for reservation '$($reservation.Name)' has available parking space. No need to increment."
	}
}

## main execution

if ($SubscriptionId) {
	Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

$vmQuery = @"
resources
| where type =~ 'microsoft.compute/virtualmachines'
| where resourceGroup =~ '$ResourceGroupName'
| extend zonesArray = todynamic(zones)
| extend vmZone = tostring(zonesArray[0])
| where vmZone == '$Zone'
| extend crgId = tostring(properties.capacityReservation.capacityReservationGroup.id)
| where isempty(crgId)
| project id, name, resourceGroup, location, vmZone, vmSize=tostring(properties.hardwareProfile.vmSize), subscriptionId
"@

$candidateVms = Search-AzGraph -Query $vmQuery

if (-not $candidateVms -or $candidateVms.Count -eq 0) {
	Write-Output @()
	return
}

$crgs = Get-AzCapacityReservationGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

$reservationLookup = @{}

foreach ($crg in ($crgs | Where-Object { $_ })) {
	$reservations = Get-AzCapacityReservation -ResourceGroupName $ResourceGroupName -CapacityReservationGroupName $crg.Name -ErrorAction SilentlyContinue
	foreach ($res in ($reservations | Where-Object { $_ })) {
		$resZone = if ($res.Zones) { [string]$res.Zones[0] } else { '' }
		$resRegion = [string]$res.Location
		$resSku = [string]$res.Sku.Name
		if ($resZone -and $resRegion -and $resSku) {
			$key = "{0}|{1}|{2}" -f $resZone.ToLowerInvariant(), $resRegion.ToLowerInvariant(), $resSku.ToLowerInvariant()
			$reservationLookup[$key] = $true
		}
	}
}

$vmsWithoutMatchingReservation = foreach ($vm in $candidateVms) {
	$key = "{0}|{1}|{2}" -f ([string]$vm.vmZone).ToLowerInvariant(), ([string]$vm.location).ToLowerInvariant(), ([string]$vm.vmSize).ToLowerInvariant()
	if (-not $reservationLookup.ContainsKey($key)) {
		[pscustomobject]@{
			VmName          = $vm.name
			VmId            = $vm.id
			ResourceGroup   = $vm.resourceGroup
			SubscriptionId  = $vm.subscriptionId
			Region          = $vm.location
			Zone            = $vm.vmZone
			VmSku           = $vm.vmSize
			HasCrgReference = $false
			MatchingReservationFound = $false
		}
	}
}
write-verbose ("Found $($vmsWithoutMatchingReservation.Count) VMs in zone '$Zone' without matching capacity reservations.")

if (!($targetCrg = Get-AzCapacityReservationGroup -ResourceGroupName $ResourceGroupName -Name $newCrg.Name -ErrorAction SilentlyContinue)) {
    $targetCrg = New-AzCapacityReservationGroup -CRGResourceGroupName $ResourceGroupName -Region $vmsWithoutMatchingReservation[0].Region -AvailabilityZone $Zone
}

write-verbose ("Using Capacity Reservation Group '$($targetCrg.Name)' for new reservations.")

# create reservations to match the machines that don't have them

$vmsWithoutMatchingReservation | where { $_.hasCrgReference -eq $false } | % { 
    $reservation = New-CapacityReservationForSku -crgName $targetCrg.Name -crgResourceGroupName $ResourceGroupName -VmSku $_.VmSku -AvailabilityZone $_.Zone
}

$reservation


