<#
.SYNOPSIS
    Enumerates every Private Endpoint in a subscription and repoints each
    Private DNS Zone Group to the equivalent zone in a TARGET subscription/RG.

.NOTES
    - Matches zones by NAME (e.g., privatelink.blob.core.windows.net).
    - Supports -DryRun to preview changes with NO modifications.
    - Logs all actions to a timestamped file.
#>

param(
    [Parameter(Mandatory = $true)][string]$SourceSubscriptionId,
    [Parameter(Mandatory = $true)][string]$TargetSubscriptionId,
    [Parameter(Mandatory = $true)][string]$TargetZoneResourceGroup,
    [Parameter(Mandatory = $false)][switch]$DryRun
)

# ----------------------------------------------------------------------
# Setup & Logging
# ----------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile    = ".\PE-Repoint-$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "s"), $Level, $Message
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

if ($DryRun) {
    Write-Log "DRY RUN MODE ENABLED — no changes will be made." "WARN"
}

# ----------------------------------------------------------------------
# Step 1: Build a lookup of TARGET zones (name -> resourceId)
# ----------------------------------------------------------------------
Write-Log "Loading target zones from subscription $TargetSubscriptionId / RG $TargetZoneResourceGroup"

Set-AzContext -SubscriptionId $TargetSubscriptionId | Out-Null

$targetZones = Get-AzPrivateDnsZone -ResourceGroupName $TargetZoneResourceGroup

$targetZoneMap = @{}
foreach ($z in $targetZones) {
    $targetZoneMap[$z.Name.ToLower()] = $z.ResourceId
}

Write-Log ("Loaded {0} target zones." -f $targetZoneMap.Count)

function Resolve-TargetZoneId {
    param([string]$ZoneName)
    $key = $ZoneName.ToLower()
    if ($targetZoneMap.ContainsKey($key)) {
        return $targetZoneMap[$key]
    }
    return $null
}

# ----------------------------------------------------------------------
# Step 2: Enumerate every Private Endpoint in the SOURCE subscription
# ----------------------------------------------------------------------
Write-Log "Switching to source subscription $SourceSubscriptionId"
Set-AzContext -SubscriptionId $SourceSubscriptionId | Out-Null

$privateEndpoints = Get-AzPrivateEndpoint
Write-Log ("Found {0} private endpoints in source subscription." -f $privateEndpoints.Count)

$summary = New-Object System.Collections.Generic.List[object]

# ----------------------------------------------------------------------
# Step 3: Process each PE and its zone group(s)
# ----------------------------------------------------------------------
foreach ($pe in $privateEndpoints) {

    $peName = $pe.Name
    $peRg   = $pe.ResourceGroupName

    Write-Log "-----------------------------------------------------------"
    Write-Log ("Processing PE: {0} (RG: {1})" -f $peName, $peRg)

    # Get existing zone group(s) for this PE
    try {
        $zoneGroups = Get-AzPrivateDnsZoneGroup `
            -ResourceGroupName $peRg `
            -PrivateEndpointName $peName
    }
    catch {
        Write-Log ("No zone group found for {0}: {1}" -f $peName, $_.Exception.Message) "WARN"
        continue
    }

    if (-not $zoneGroups) {
        Write-Log ("PE {0} has no DNS zone group. Skipping." -f $peName) "WARN"
        continue
    }

    foreach ($zg in $zoneGroups) {

        $newConfigs = @()
        $changeNeeded = $false

        foreach ($cfg in $zg.PrivateDnsZoneConfigs) {

            # Extract the zone NAME from the existing (source) zone resource id
            $sourceZoneId   = $cfg.PrivateDnsZoneId
            $sourceZoneName = ($sourceZoneId -split '/')[-1]

            $targetZoneId = Resolve-TargetZoneId -ZoneName $sourceZoneName

            if (-not $targetZoneId) {
                Write-Log ("  No matching TARGET zone for '{0}' (PE {1}). Keeping original." -f $sourceZoneName, $peName) "ERROR"
                # Preserve existing config so we don't drop it
                $newConfigs += New-AzPrivateDnsZoneConfig `
                    -Name $cfg.Name `
                    -PrivateDnsZoneId $sourceZoneId
                continue
            }

            if ($sourceZoneId -ieq $targetZoneId) {
                Write-Log ("  Zone '{0}' already points at target. No change." -f $sourceZoneName)
                $newConfigs += New-AzPrivateDnsZoneConfig `
                    -Name $cfg.Name `
                    -PrivateDnsZoneId $sourceZoneId
                continue
            }

            Write-Log ("  Repointing '{0}'" -f $sourceZoneName)
            Write-Log ("     FROM: {0}" -f $sourceZoneId)
            Write-Log ("     TO  : {0}" -f $targetZoneId)

            $changeNeeded = $true

            $newConfigs += New-AzPrivateDnsZoneConfig `
                -Name $cfg.Name `
                -PrivateDnsZoneId $targetZoneId
        }

        # Record for summary
        $summary.Add([PSCustomObject]@{
            PrivateEndpoint = $peName
            ResourceGroup   = $peRg
            ZoneGroup       = $zg.Name
            ChangeNeeded    = $changeNeeded
        })

        # Apply (unless dry run)
        if ($changeNeeded) {
            if ($DryRun) {
                Write-Log ("  [DRY RUN] Would update zone group '{0}' on PE '{1}'." -f $zg.Name, $peName) "WARN"
            }
            else {
                try {
                    Set-AzPrivateDnsZoneGroup `
                        -ResourceGroupName $peRg `
                        -PrivateEndpointName $peName `
                        -Name $zg.Name `
                        -PrivateDnsZoneConfig $newConfigs | Out-Null

                    Write-Log ("  ✅ Updated zone group '{0}' on PE '{1}'." -f $zg.Name, $peName)
                }
                catch {
                    Write-Log ("  ❌ FAILED updating PE '{0}': {1}" -f $peName, $_.Exception.Message) "ERROR"
                }
            }
        }
        else {
            Write-Log ("  No changes required for zone group '{0}'." -f $zg.Name)
        }
    }
}

# ----------------------------------------------------------------------
# Step 4: Summary
# ----------------------------------------------------------------------
Write-Log "==========================================================="
Write-Log "SUMMARY"
$summary | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_ }

Write-Log ("Log written to: {0}" -f $logFile)
Write-Log "Done."