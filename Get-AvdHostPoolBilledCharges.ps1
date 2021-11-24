# Get-AvdHostPoolBilledCharges.ps1
# by Ken Hoover <ken.hoover@microsoft.com>
# November 2021

# Takes an AVD host pool name as a parameter and returns info on the billed charges for the VM's that are members 
# of the pool between the start and end dates specified.
#
# This does not consider network-based costs such as data ingress/egress but that's usually a small fraction of
# the total cost anyway.

# If the start/end dateTime values are not specified, the script will default to the last 30 days.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][String]$AVDHostPoolName,
    [Parameter(Mandatory = $false)][datetime]$StartDate,
    [Parameter(Mandatory = $false)][datetime]$EndDate
)

# If we didn't get a start and/or end time, default to the last 30 days
if (($null -eq $StartDate) -or ($null -eq $EndDate)) {
    $StartDate = (Get-Date).AddDays(-30)
    $EndDate = (Get-Date)
}

if ($EndDate -lt $StartDate) {
    Write-Error "ETIMETRAVELFORBIDDEN:  End date must be later than start date"
}

Write-Verbose "Getting billed charges for AVD host pool $AVDHostPoolName between $StartDate and $EndDate"

# Find the host pool.  Doing it this way means we don't need to bug the user for the
# RG name of the host pool.
$HostPool = Get-AzWvdHostPool | where {$_.name -eq $AVDHostPoolName}
if (!($HostPool)) {
    Write-Error "No host pool found with name $AVDHostPoolName in current subscription."
    exit 
}

$hostPoolRGName = (Get-AzResource -ResourceId $HostPool.Id).ResourceGroupName
Write-Verbose "Host pool $AvdHostPoolName found in resource group $hostPoolRGName"

# Get the session hosts in the target pool
$SessionHosts = Get-AzWvdSessionHost -HostPool $HostPool.Name -ResourceGroupName $hostPoolRGName

if ($SessionHosts.Count -eq 0) {
    Write-Error "No session hosts found in host pool $AVDHostPoolName"
    exit 
} else {
    Write-Verbose ("Host pool $AvdHostPoolName has " + $SessionHosts.Count + " session hosts.")
}

$SessionHostVms = @()
Write-Verbose "Retriving Session host VM information..."
$sessionhosts.ResourceId | % { 
    $SessionHostResourceObj = Get-AzResource -ResourceId $_
    if ($SessionHostResourceObj) {
        $SessionHostVms += get-azvm -ResourceGroupName $SessionHostResourceObj.ResourceGroupName -Name $SessionHostResourceObj.Name
    } else {
        write-warning "Unable to retrieve VM resource for " + $SessionHosts.Name
    }
}

# Build a list of the resource ID's for billable "stuff" that makes up the session hosts
# Compute, disk, NICs, what else?
# Need to accommodate cases where machines have multiple attached disks and NICs

$ComputeResourceIds = @()
$OSDiskResourceIds = @()
$DataDiskResourceIds = @()
$allResources = @()


Write-Verbose "Retrieving resource information for compute and disk resources... "
$SessionHostVms | % {

    $VmResourceGroupName = $_.ResourceGroupName
    $ComputeResourceIds += $_.Id
    $allResources += Get-AzResource -ResourceId $_.Id

    $OSDiskResourceIds += $_.StorageProfile.OsDisk.ManagedDisk.Id
    $allResources += Get-AzResource -ResourceId $_.StorageProfile.OsDisk.ManagedDisk.Id
    
    if ($_.StorageProfile.DataDisks.count -gt 1) {
        $_.StorageProfile.DataDisks | % {
            $disk = Get-AzDisk -ResourceGroupName $VmResourceGroupName -DiskName $_.StorageProfile.DataDisks.name
            $datadiskResourceIds += $disk.Id
            $allResources += Get-AzResource -ResourceId $disk.Id
        }
    } else {
        $disk = Get-AzDisk -ResourceGroupName $VmResourceGroupName -DiskName $_.StorageProfile.DataDisks.name
        $datadiskResourceIds += $disk.Id
        $allResources += Get-AzResource -ResourceId $disk.Id
    }
}

$allResourceIds = ($allResources).id

Write-Verbose ("Retrieved " + $ComputeResourceIds.count + " Compute resource(s)")
Write-Verbose ("Retrieved " + $OSDiskResourceIds.count + " OS disk resource(s)")
Write-Verbose ("Retrieved " + $DataDiskResourceIds.count + " data disk resource(s)")

Write-Verbose "Retrieving resource information..."

# Retrieving Consumption Data...
$allConsumption = Get-AzConsumptionUsageDetail -ResourceGroup $hostPoolRGName

# Write-Verbose "Retrieving billing data for compute resources..."
# $allConsumption = $ComputeResourceIds | % { 
#     Get-AzConsumptionUsageDetail -InstanceId $_ -StartDate $StartDate -EndDate $EndDate -IncludeMeterDetails
# }

# Write-Verbose "Retrieving billing data for OS disk resources..."
# $allConsumption += $OSDiskResourceIds | % { 
#     Get-AzConsumptionUsageDetail -InstanceId $_ -StartDate $StartDate -EndDate $EndDate -IncludeMeterDetails
# }
# Write-Verbose "Retrieving billing data for Data disk resources..."
# $allConsumption += $DataDiskResourceIds | % { 
#     Get-AzConsumptionUsageDetail -InstanceId $_ -StartDate $StartDate -EndDate $EndDate -IncludeMeterDetails  
# }

$costData = @()

$allConsumption | % {
    $targetResourceId = $_.InstanceId
    $o = New-Object -TypeName PSObject
    $o | Add-Member -MemberType NoteProperty -Name "ResourceName" -Value ($allResources | where {$_.id -eq $targetResourceId}).name
    $o | Add-Member -MemberType NoteProperty -Name "ResourceType" -Value ($allResources | where {$_.id -eq $targetResourceId}).type
    $o | Add-Member -MemberType NoteProperty -Name "ResourceId" -Value $targetResourceId
    $o | Add-Member -MemberType NoteProperty -Name "PreTaxCost" -Value ([math]::Round($_.PretaxCost,2))
    $costData += $o
    $totalcost += [math]::Round($_.PreTaxCost,2)
}

$totalCostStr = ($totalcost).ToString() + " (" + $allConsumption[0].Currency + ")"

$computeCost = 0.0
$storageCost = 0.0

$costData | format-table PreTaxCost,resourceType,ResourceName

$costData | where {$_.ResourceType -eq "Microsoft.Compute/virtualMachines"} | % {
    $computeCost += [math]::Round($_.PreTaxCost,2)
}

$costData | where {$_.ResourceType -eq "Microsoft.Compute/disks"} | % {
    $storageCost += [math]::Round($_.PreTaxCost,2)
}

Write-Output "======================================================================================="
Write-Output "Total billed cost for compute and disk in host pool $AVDhostpoolName is $totalCostStr"
Write-Output ("Total compute cost is " + $computeCost.ToString() +  " (" + $allConsumption[0].Currency + ")")
Write-Output ("Total disk (storage) cost is " + $storageCost.toString() + " (" + $allConsumption[0].Currency + ")")
Write-Output "======================================================================================="
Write-warning ("Due to rounding, some resources may show zero cost when the actual value is nonzero")





