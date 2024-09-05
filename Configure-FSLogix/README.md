# Configure-FSLogix.ps1

This Powershell scrupt creates registry entries to enable FSLogix profile containers on the target machine.  This is intended for "manual" enablement of FSLogix.  It's better to use a configuration management tool like Intune for this of course.

Full documentation about these registry keys and other configuration settings used by FSLogix is [here](https://learn.microsoft.com/en-us/fslogix/reference-configuration-settings?tabs=profiles).

## Script Content (with annotations)

---

`New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name Enabled -Type DWORD -Value 1 -Force`

This registry key is the master "on" switch for FSLogix.  If it is not set to "1" then FSLogix will take no action.

---

`New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name IgnoreNonWVD -Type DWORD -Value 1 -Force`

This setting tells FSLogix to not take any action if the login attempt is not coming through AVD/Windows365.  This is useful for troubleshooting, especially when the `PreventLoginWithFailure` setting is enabled.

---

`New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name IsDynamic -Type DWORD -Value 1 -Force`

This setting tells FSLogix that we on;y want to use dynamic VHDs (`.vhdx` extension)

---

`New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name PreventLoginWithFailure -Type DWORD -Value 1 -Force`

This setting will block a user from logging in if the profile VHD cannot be mounted for some reason and show an error message indicating whatn went wrong.

---

`New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name Se-tTempToLocalPath -Type DWORD -Value 1 -Force`

This setting tells FSLogix to redirect the default temporary file paths like C:\TEMP to point to the local disk instead of redirecting them to the remote VHD.

---

`New-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name VHDLocations -type String -Value $VHDLocations -Force`

This value contains the full SMB path to the file share where the user's VHDX should be created.
