# Input bindings are passed in via param block.
param ($Timer)

<#
.SYNOPSIS
    Automated process of starting and stopping WVD session hosts based on user sessions.
.DESCRIPTION
    This script is intended to automatically start and stop session hosts in a Windows Virtual Desktop
    host pool based on the number of users.  
    The script determines the number of Session Hosts that should be running by adding the number of sessions 
    in the pool to a threshold. The threshold is the number of sessions available between each script run
    to accommodate new connections.  Those two numbers are added and divided by the maximum sessions per host.  
    The maximum session is set in the depth-first load balancing settings.  
    Session hosts are stopped or started based on the number of session hosts
    that should be available compared to the number of hosts that are running.

    Requirements:
    WVD Host Pool must be set to Depth First
    An Azure Function App
        Use System Assigned Managed ID
        Give contributor rights for the Session Host VM Resource Group to the Managed ID
   The script requires the following PowerShell Modules and are included in PowerShell Functions by default
        az.compute 
        az.desktopvirtualization
    For best results set a GPO to log out disconnected and idle sessions
    Full details can be found at:
    https://www.ciraltos.com/auto-start-and-stop-session-hosts-in-windows-virtual-desktop-spring-update-arm-edition-with-an-azure-function/
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it
    Author      : Travis Roberts
    Contributor : Kandice Hendricks
    Website     : www.ciraltos.com & https://www.greenpages.com/
    Version     : 1.0.0.0 Initial Build for WVD ARM.  Adapted from previous start-stop script for WVD Fall 2019
                    Updated for new az.desktopvirtulization PowerShell module and to run as a Function App
#>

#region VARIABLES
# View Verbose data
# Set to "Continue" to see Verbose data
# set to "SilentlyContinue" to hide Verbose data
$VerbosePreference = "Continue"

# Host Pool Name
$hostPoolName = '<enter host pool name>'

# Session Host Resource Group
# Session Hosts and Host Pools can exist in different Resource Groups, but are commonly the same
# Host Pool Resource Group and the resource group of the Session host VM's.
$hostPoolRg = '<enter Host Pool resource group>'
$sessionHostVmRg = '<enter VM resource group>'

# Server start threshold
# Number of available sessions to trigger a server start or shutdown
$serverStartThreshold = <enter threshold value>

# Peak time and Threshold settings
# Set usePeak to "yes" to enable peak time
# Set the Peak Threshold, Start and Stop Peak Time,
# Set the time zone to use, use "Get-TimeZone -ListAvailable" to list ID's
$usePeak = "<enter yes or no, update settings below>"
$peakServerStartThreshold = <enter threshold value>
$startPeakTime = '08:00:00'
$endPeakTime = '18:00:00'
$timeZone = "Eastern Standard Time"
$peakDay = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'
$minimumRunningVMs = <enter minimum number of vms to run>
$peakMinimumRunningVMs = <enter minimum number of vms to run>
#endregion VARIABLES

#region FUNCTIONS
function Start-SessionHost
{
	param (
		$sessionHosts,
		$hostsToStart
	)
	
	# Number of off session hosts accepting connections
	$offSessionHosts = $sessionHosts | Where-Object { $_.Status -eq "Unavailable" }
	$offSessionHostsCount = $offSessionHosts.count
	Write-Verbose "Off Session Hosts $offSessionHostsCount"
	Write-Verbose ($offSessionHosts | Out-String)
	
	if ($offSessionHosts.Count -eq 0)
	{
		Write-Error "Start threshold met, but there are no hosts available to start"
	}
	else
	{
		if ($hostsToStart -gt $offSessionHostsCount)
		{
			$hostsToStart = $offSessionHosts
		}
		Write-Verbose "Conditions met to start a host"
		$counter = 0
		while ($counter -lt $hostsToStart)
		{
			$startServerName = ($offSessionHosts | Select-Object -Index $counter).name
			Write-Verbose "Server to start $startServerName"
			try
			{
				# Start the VM
				$vmName = ($startServerName -split { $_ -eq '.' -or $_ -eq '/' })[1]
				Start-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName
			}
			catch
			{
				$ErrorMessage = $_.Exception.message
				Write-Error ("Error starting the session host: " + $ErrorMessage)
				Break
			}
			$counter++
		}
	}
}

function Stop-SessionHost
{
	param (
		$sessionHosts,
		$hostsToStop
	)
	# Get computers running with no users
	$emptyHosts = $sessionHosts | Where-Object { $_.Session -eq 0 -and $_.Status -eq 'Available' }
	$emptyHostsCount = $emptyHosts.count
	Write-Verbose "Evaluating servers to shut down"
	
	if ($emptyHostsCount -eq 0)
	{
		Write-error "No hosts available to shut down"
	}
	else
	{
		if ($hostsToStop -ge $emptyHostsCount)
		{
			$hostsToStop = $emptyHostsCount
		}
		Write-Verbose "Conditions met to stop a host"
		$counter = 0
		while ($counter -lt $hostsToStop)
		{
			$shutServerName = ($emptyHosts | Select-Object -Index $counter).Name
			Write-Verbose "Shutting down server $shutServerName"
			try
			{
				# Stop the VM
				$vmName = ($shutServerName -split { $_ -eq '.' -or $_ -eq '/' })[1]
				Stop-AzVM -ErrorAction Stop -ResourceGroupName $sessionHostVmRg -Name $vmName -Force
			}
			catch
			{
				$ErrorMessage = $_.Exception.message
				Write-Error ("Error stopping the VM: " + $ErrorMessage)
				Break
			}
			$counter++
		}
	}
}
#endregion FUNCTIONS

#region SCRIPT EXECUTION

# Get Host Pool 
try
{
	$hostPool = Get-AzWvdHostPool -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName
	Write-Verbose "HostPool:"
	Write-Verbose $hostPool.Name
}
catch
{
	$ErrorMessage = $_.Exception.message
	Write-Error ("Error getting host pool details: " + $ErrorMessage)
	Break
}

# Verify load balancing is set to Depth-first
if ($hostPool.LoadBalancerType -ne "DepthFirst")
{
	Write-Error "Host pool not set to Depth-First load balancing.  This script requires Depth-First load balancing to execute"
	exit
}

# Check if peak time and adjust threshold
# Warning! will not adjust for DST
if ($usePeak -eq "yes")
{
	$utcDate = ((get-date).ToUniversalTime())
	$tZ = Get-TimeZone $timeZone
	$date = [System.TimeZoneInfo]::ConvertTimeFromUtc($utcDate, $tZ)
	write-verbose "Date and Time"
	write-verbose $date
	$dateDay = (((get-date).ToUniversalTime()).AddHours($utcOffset)).dayofweek
	Write-Verbose $dateDay
	$startPeakTime = get-date $startPeakTime
	$endPeakTime = get-date $endPeakTime
	if ($date -gt $startPeakTime -and $date -lt $endPeakTime -and $dateDay -in $peakDay)
	{
		Write-Verbose "Adjusting threshold for peak hours"
		$serverStartThreshold = $peakServerStartThreshold
		$minimumRunningVMs = $peakMinimumRunningVMs
	}
}

# Get the Max Session Limit on the host pool
# This is the total number of sessions per session host
$maxSessions = $hostPool.MaxSessionLimit
Write-Verbose "MaxSession:"
Write-Verbose $maxSessions

# Find the total number of session hosts
# Exclude servers in drain mode and do not allow new connections
try
{
	$allAvailableVMs = Get-AzWvdSessionHost -ResourceGroupName $hostPoolRg -HostPoolName $hostPoolName | Where-Object { $_.AllowNewSession -eq $true }
	# Get current active user sessions
	$currentUserSessions = 0
	foreach ($sessionHost in $allAvailableVMs)
	{
		$count = $sessionHost.session
		$currentUserSessions += $count
	}
	Write-Verbose "CurrentSessions"
	Write-Verbose $currentUserSessions
}
catch
{
	$ErrorMessage = $_.Exception.message
	Write-Error ("Error getting session hosts details: " + $ErrorMessage)
	Break
}

# Number of running and available session hosts
# Hosts that are shut down are excluded
$allRunningVMs = $allAvailableVMs | Where-Object { $_.Status -eq "Available" }
$currentActiveVMs = $allRunningVMs.count
Write-Verbose "Active WVD Machines $currentActiveVMs"
Write-Verbose ($allRunningVMs | Out-string)

# Target number of servers required running based on active sessions, Threshold and maximum sessions per host
$VMs_Target = [math]::Ceiling((($currentUserSessions + $serverStartThreshold) / $maxSessions))

if (($currentActiveVMs -lt $VMs_Target) -or ($currentActiveVMs -lt $minimumRunningVMs))
{
	Write-Verbose "Running session host count $allRunningVMs is less than session host target count $VMs_Target, run start function"
	# set $VMsToStart to the 'default' value
	$VMsToStart = ($VMs_Target - $currentActiveVMs)
	# test $VMsToStart to see if it matches a certain value
	if ($VMsToStart -lt ($minimumRunningVMs - $currentActiveVMs))
	{
		# if it's lower, then force it to be the higher value
		$VMsToStart = ($minimumRunningVMs - $currentActiveVMs)
	}
	Start-SessionHost -sessionHosts $allAvailableVMs -hostsToStart $VMsToStart
}
elseif (($currentActiveVMs -gt $VMs_Target) -or ($currentActiveVMs -gt $minimumRunningVMs))
{
	Write-Verbose "Running session hosts count $currentActiveVMs is greater than session host target count $VMs_Target, run stop function"
	# set $VMsToStop to the 'default' value
	$VMsToStop = ($currentActiveVMs - $VMs_Target)
	# test $VMsToStop to see if it matches a certain value
	if ($VMsToStop -gt ($currentActiveVMs - $minimumRunningVMs))
	{
		# if it's higher, then force it to be the lower value
		$VMsToStop = ($currentActiveVMs - $minimumRunningVMs)
	}
	Stop-SessionHost -SessionHosts $allAvailableVMs -hostsToStop $VMsToStop
}
else
{
	Write-Verbose "Running session host count $currentActiveVMs matches session host target count $VMs_Target, doing nothing"
}
#endregion SCRIPT EXECUTION