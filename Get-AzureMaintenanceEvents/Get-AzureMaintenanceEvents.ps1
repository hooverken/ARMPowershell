# Get-AzureMaintenanceEvents.ps1
# by Ken Hoover <moc.tfosorcim@revooh.nek>
# Jan 2025

# This script polls for pending maintenance events on an Azure VM.
# If one is found it logs the event to the Application event log on the local machine.
# A data collection rule can be used to collect the event and send it to a Log Analytics workspace.

# This script is intended to be run as a scheduled task on an Azure VM.

#Requires -Version 7

[CmdletBinding()]
param (
    [Parameter(mandatory=$false)][Switch]$Test,
    [Parameter(mandatory=$false)][Switch]$Setup,
    [Parameter(mandatory=$false)][Switch]$Run,
    [Parameter(mandatory=$false)][PSCredential]$Credential
)


if ($setup) {

    # This is a setup run.  We need to create the event log source and set up the scheduled task

    # Create event log source if it doesn't exist.
    if (-not (Get-EventLog -LogName Application -Source "AzureMaintenanceEvents" -ErrorAction SilentlyContinue)) {
        New-EventLog -LogName Application -Source "AzureMaintenanceEvents"
    }

    # Set up the scheduled task to start at system startup.
    $action = New-ScheduledTaskAction -Execute "C:\"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = $Credential.UserName
    $settings = New-ScheduledTaskSettingsSet
    $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings
    Register-ScheduledTask -Name PollForAzureMaintenanceEvents -InputObject $task

    exit
}

if ($test) {
    # Writes a test entry to thye event log and exits.
    # This is useful for testing the data collection rule and alert rules that need to trigger on the event.

    Write-Host "Writing dummy event to Application Log."

    # Note the test log entry is EventID 7665 and a "real" event entry is 5667

    $e = [ordered]@{
        "EventId" = "11111111-1111-1111-1111-111111111111"
        "EventType" = "TEST"
        "ResourceType" = "VirtualMachine"
        "Resources" = "ResourceName[]"
        "EventStatus" = "Scheduled"
        "NotBefore" = "2025-01-01T00:00:00Z"
        "Description" = "This is a test event to exercise the logging."
    }

    Write-EventLog -LogName Application -Source "AzureMaintenanceEvents" -EventId 7665 -EntryType Warning -Message ($e | ConvertTo-Json)

    exit 
}

if ($run) {
    # This is the main run loop.  It will poll for maintenance events and log them to the event log.

        $lastDocumentIncarnation = 0
    while ($true) {

        # Check if there is a pending maintanence event for this VM.

        $result = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" | ConvertTo-Json -Depth 64

        if ($null -ne $result.events) {  # Check if the "events" property contains something.

            # We got something back.

            # check if there is a change from previous entries (will have higher documentIncarnation value than before)

            if ($result.documentIncarnation -gt $lastDocumentIncarnation) {
                $lastDocumentIncarnation = $result.documentIncarnation

                # Since there's something new here, get to work.

                Write-Verbose ("Maintenance event found: " + $result.events)

                # Log it
                ForEach-Object ($result.events) {

                    # EventID in this structure is the Azure maintenance event ID (a GUID),
                    # not the event ID that will be stamped as part of the event log entry.
                    
                    $e = [ordered]@{
                        "EventId" = $_.EventId
                        "EventType" = $_.EventTypemm
                        "Resources" = $_.Resources
                        "EventStatus" = $_.EventStatus
                        "NotBefore" = $_.NotBefore
                        "Description" = $_.Description
                    }

                    Write-EventLog -LogName Application -Source "AzureMaintenanceEvents" -EventId 5667 -EntryType Information -Message ($e | ConvertTo-Json)

                }
            } else {
                # No change, sleep for a bit and try again.
                Write-Verbose "No change in maintenance events."
                continue
            }
        }
        Write-Verbose ("Nothing returned.  Sleeping 15s..." )
        Start-Sleep -Seconds 15 
    }
}
