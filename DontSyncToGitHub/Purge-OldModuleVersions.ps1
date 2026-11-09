# Purge-OldModuleVersions.ps1
# by Ken Hoover ken.hoover@microsoft.com

# This script will take a module name and loop through its sub-modules to uninstall all but the newest
# version of each one.

# Example:
#
# Powershell module Foo has lots of submodules like Foo.Puppies, Foo.Kittens and Foo.Lemurs
# There can be more than one version of the submodules installed simultaneously which can cause issues
# when importing because the most recent version of Foo.Kittens might need Foo.Lemurs to function but the
# version of Foo.Lemurs that was important is not compatible so Foo.Kittens doesn't work right.  This produces and
# error message like this one: 

# Write-Error: This module requires <Submodule> version 2.5.1. An earlier version of <SubModule> is imported 
# in the current PowerShell session. Please open a new session before importing this module. This error 
# could indicate that multiple incompatible versions of the Azure PowerShell cmdlets are installed on your system. 
# Please see https://aka.ms/azps-version-error for troubleshooting information.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][String]$MainModule
)

# get the list of submodules in the module name presented

Write-Verbose ("Uninstalling older versions of module $Mainmodule")
$Latest = Get-InstalledModule $MainModule; 
Get-InstalledModule $MainModule -AllVersions | ? {$_.Version -ne $Latest.Version} | Uninstall-Module -Verbose
