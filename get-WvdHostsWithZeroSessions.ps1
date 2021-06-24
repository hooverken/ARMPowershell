# Get-WvdHostsWithZeroSessions.ps1
# by Ken Hoover <ken.hoover@microsoft.com>
#
# This script will identify any session hosts which are running but have no actuve user connections
# This is intended for use with a process that shuts down session hosts that don't have any active connections
#

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][String]$HostPoolName
)

# Get the acgive session hosts for the specified host pool name
$hostpool = Get-AzWvdHostPool | Where-Object {$_.name -eq $HostPoolName }
$rgname = (Get-AzResource -id $hostpool.id).ResourceGroupName
$activeSessionHosts = Get-AzWvdSessionHost -ResourceGroupName $rgname -HostPoolName $hostpool.Name | where { $_.Status -eq "Available"}
$activeSessionHostVMs = Get-AzResource -id $activeSessionHosts.ResourceId


# Get list of active sessions for the host pool
$activeSessions = Get-AzWvdUserSession -HostPoolName $hostpool.Name -ResourceGroupName $rgname


$activeSessionHosts
$activesessions
$activeSessionHostVMs