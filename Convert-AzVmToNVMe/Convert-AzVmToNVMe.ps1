# Convert-AzVmToNVMe.ps1
# by Ken Hoover <ken.hoover@microsoft.com>
# June 2025

# Converts the named VM from a non-v6 VM to a V6 machine.  Since V6 VMs are NVMe only this requires some work.

# Ref: https://techcommunity.microsoft.com/blog/sapapplications/converting-azure-virtual-machines-running-windows-from-scsi-to-nvme/4192583 

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)][string]$VirtualMachineName,
    [Parameter(mandatory = $true)][string]$newSize,
    [Parameter(mandatory = $false)][pscredential]$credential,
    [Parameter(mandatory = $false)][switch]$handleDeleteWithVM
)


# These commands must be run on the target VM to make it re-detect its storage controller and disks on boot
$registryChanges = {
    reg delete HKLM\SYSTEM\CurrentControlSet\Services\stornvme\StartOverride /f 
    reg ADD "HKLM\SYSTEM\CurrentControlSet\services\stornvme" /v "ErrorControl" /t REG_DWORD /d 0 /f 
    reg ADD "HKLM\SYSTEM\CurrentControlSet\services\stornvme\StartOverride" /v 0 /t REG_DWORD /d 0 /f
}

# ========================================================================================

# Get the VM object to confirm that it exists.
$vm = Get-AzVM -Status | where { $_.name -eq $VirtualMachineName}

if (!($vm)) {
    write-warning ("$virtualMachineName not found in current subscription.")
    exit 
}

$RGname = $vm.ResourceGroupName


# Identify network interfaces associated with the VM
$networkProfile = $vm.NetworkProfile
if ($networkProfile.NetworkInterfaces.count -ge 2) {
    $nics = @()
    $networkProfile.NetworkInterfaces | % { 
        $nics += Get-AzNetworkInterface -ResourceId $_.Id
    }
} else {
    $nics = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces.id
}

# Identify all disks associated with the VM
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

# Check if the NIC is configured to delete itself if the Compute resource is deleted
$nics | % { 
    if ($_.DeleteOption -eq "Delete") {
        if ($handleDeleteWithVM) {
            # Reconfigure the NIC to not delete itself when the Compute resource is deleted
            Write-Host "Reconfiguring NIC $($_.Name) to not delete itself when the Compute resource is deleted."
            $nic = | Set-AzNetworkInterface -DeleteOption "Detach" -Force
        } else {
            Write-Error "NIC $($_.Name) is configured to delete itself when its associated Compute resource is deleted. Please reconfigure it before proceeding."
            exit
        }
    } else {
        Write-Host "NIC $($_.Name) is not configured to delete itself when the Compute resource is deleted."
    }
}

# Check if the OS disk is configured to delete itself if the Compute resource is deleted
if ($osdisk.DeleteOption -eq "Delete") {
    if ($handleDeleteWithVM) {
        # Reconfigure the OS disk to not delete itself when the Compute resource is deleted
        Write-Host "Reconfiguring OS disk $($osdisk.Name) to not delete itself when the Compute resource is deleted."
        $osdisk = Set-AzDisk -Disk $osdisk -DeleteOption "Detach" -Force
    } else {
        Write-Error "OS disk $($osdisk.Name) is configured to delete itself when its associated Compute resource is deleted. Please reconfigure it before proceeding."
        exit
    }
}

# Check if the data disks are configured to delete themselves if the Compute resource is deleted
if ($datadisks) {
    $datadisks | % { 
        if ($_.DeleteOption -eq "Delete") {
            if ($handleDeleteWithVM) {
                # Reconfigure the data disk to not delete itself when the Compute resource is deleted
                Write-Host "Reconfiguring data disk $($_.Name) to not delete itself when the Compute resource is deleted."
                $_ = Set-AzDisk -Disk $_ -DeleteOption "Detach" -Force
            } else {
                Write-Error "Data disk $($_.Name) is configured to delete itself when its associated Compute resource is deleted. Please reconfigure it before proceeding."
                exit
            }
        }
    }
}

# ========================================================================================
# This process involves deleting the VM's compute instance and then creating a new compute instance
# with the same name.  The NIC and disks will be reattached to the new compute instance so it should (!) boot and run normally.

# Make sure the VM is stopped
if ($vm.PowerState -eq "VM Running") {
    Write-Host "Stopping VM $VirtualMachineName..."
    try {
        Stop-AzVM -Name $vm.Name -ResourceGroupName $RGname -Force -Verbose}
    catch {
        Write-Error "Failed to stop VM $VirtualMachineName. Please ensure the VM is not in a failed state or already stopped."
        exit
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