# Exterminate-AzureVM.ps1

# Deletes all components of the target VM -- compute, OS disk, data disk(s) and NIC(s)
# Does NOT ask for confirmation.  Make sure you know what you're doing!

# by Ken Hoover <ken.hoover@microsoft.com>
# January 2021

# TODO / Future Enhancement:  Include deleting public IP's associated with the VM.

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$VirtualMachineName
)

$vm = Get-AzVM | where { $_.name -eq $VirtualMachineName}

if (!($vm)) {
    write-warning ("$virtualMachineName not found.")
    exit 
}

$RGname = $vm.ResourceGroupName
$networkProfile = $vm.NetworkProfile
if ($networkProfile.NetworkInterfaces.count -ge 2) {
    $nics = @()
    $networkProfile.NetworkInterfaces | % { 
        $nics += Get-AzNetworkInterface -ResourceId $_.Id
    }
} else {
    $nics = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces.id
}


$storageProfile = $vm.StorageProfile
$osdisk = $storageProfile.OsDisk
if ($StorageProfile.DataDisks.count -ge 2) {
    $datadisks = @()
    $StorageProfile.DataDisks | % { 
        $datadisks += $_
    }
} else {
    if ($storageProfile.DataDisks.count -eq 1) {
        $datadisks = $storageProfile.DataDisks[0]
    }
}

Write-host "Removing compute resource $virtualMachineName..."
Remove-AzVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Verbose -Force

Write-host "Removing data disks for $virtualMachineName..."
if ($datadisks) {
    $datadisks | % { 
        Remove-AzDisk -DiskName $_.Name -ResourceGroupName $RGname -Verbose -Force
    }
} else {
    Write-Output "$VirtualMachineName has no data disks to remove."
}

Write-host "Removing OS disk for $virtualMachineName..."
Remove-AzDisk -DiskName $osdisk.Name -ResourceGroupName $RGname -Verbose -Force

Write-host "Removing NICs for $virtualMachineName..."
$nics | % { 
    $_ | Remove-AzNetworkInterface -Force
}