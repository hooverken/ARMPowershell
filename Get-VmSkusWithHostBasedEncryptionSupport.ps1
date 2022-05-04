# Get-VmSkusWithHostBasedEncryptionSupport.ps1
# Returns list of VM sizes (skus) in target region which support host-based encryption
# by Ken Hoover (kendothooveratmicrosoftdotcom)
# May 2022

# Lifted from https://docs.microsoft.com/en-us/azure/virtual-machines/windows/disks-enable-host-based-encryption-powershell#finding-supported-vm-sizes

# Add the -Invert parameter to the command line to get the list of VM's which do >>NOT<< support
# host-based encryption.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][String]$Location,  # the region to check
    [Parameter(Mandatory=$false)][switch]$Invert   # invert the output (return machines which do NOT support HBE)
)

$vmSizes=Get-AzComputeResourceSku | where-object {$_.ResourceType -eq 'virtualMachines' -and $_.Locations.Contains($Location)} 

$isSupported = 0

foreach($vmSize in $vmSizes)
{
    foreach($capability in $vmSize.capabilities)
    {
        # if this VM size supports host-based encryption, let it go through to the pipeline
        if ($capability.Name -eq 'EncryptionAtHostSupported') {
            if (($capability.Value -eq 'true') -and ($invert -ne $true)) {
                $isSupported = 1
                $vmSize
            } else {
                if (($capability.Value -eq 'false') -and ($invert -eq $true)) {
                    $vmSize
                }
            }
        }
    }
}
