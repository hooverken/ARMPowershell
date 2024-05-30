# configure-FSLogix.ps1
# By Ken Hoover <com.microsoft@hoover.ken>
# May 2024
# Performs minimal FSLogix configuration to get it working, this is heklpful when building a machine so it works
# before a GPO can take over these settings.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][String]$VHDLocations
)

# The master "on" switch for FSLogix Profiles
New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name Enabled -Type DWORD -Value 1 -Force

# Tells FSLogix to not  kick in if this login is not via AVD
New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name IgnoreNonWVD -Type DWORD -Value 1 -Force

# Use dynamic VHDs (.vhdx) instead of fixed size
New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name IsDynamic -Type DWORD -Value 1 -Force

# Prevents login if FSLogix can't mount the VHD
New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name PreventLoginWithFailure -Type DWORD -Value 1 -Force

# Tells FSLogix to use the local disk for temporary storage
New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name SetTempToLocalPath -Type DWORD -Value 1 -Force

# The file share path to look for the prodile VHD
New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name VHDLocations -type REG_SZ -Value $VHDLocations -Force

