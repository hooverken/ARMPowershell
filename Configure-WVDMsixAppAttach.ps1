# Configure-WVDMsixAppAttach.ps1
# by Ken Hoover <ken dot hoover at microsoft dotcom> for Microsoft Corporation
# December 2020

# This script automates some of the work of setting up a MSIX app attach environment for WVDMsixAppAttach

# Prerequisites
# Ref: https://docs.microsoft.com/en-us/azure/virtual-desktop/app-attach-azure-portal

# Step 1:  Turn off automatic updates  for MSIX App attach applications

# Disable Store auto update via Reg key
New-ItemProperty -path "HKLM\Software\Policies\Microsoft\WindowsStore" -Name AutoDownload -PropertyType REG_DWORD -value 0
Disable-ScheduledTask -Taskname "\Microsoft\Windows\WindowsUpdate\Automatic app update" -Force 
Disable-ScheduledTask -Taskname "\Microsoft\Windows\WindowsUpdate\Scheduled Start" -Force

# Disable Content Delivery auto download apps that they want to promote to users:
New-ItemProperty -path "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name PreInstalledAppsEnabled -PropertyType REG_DWORD -Value 0

New-ItemProperty -path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Debug" -Name ContentDeliveryAllowedOverride -PropertyType REG_DWORD -Value 0x2

# Disable Windows Update:
Set-Service wuauserv -StartupType Disabled -Force

# Make sure that Hyper-V is installed
if ((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online).State -ne "Enabled") {
    write-warning "The Hyper-V optional feature must be enabled to use MSIX App attach."
    Write-Warning "Use `"Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`" to enable."
    Write-warning "This will require restarting the system."
    exit 
}

# Make sure the Az.DesktopVirtualization module is installed.
if (Get-Module | Where-Object { $_.name.contains("DesktopVirtualization") }) { 
    Write-Verbose ("Az.DesktopVirtualization module is present.")
} else {
    write-warning ("The Az.DesktopVirtualization module is not installed.")
    exit 
}