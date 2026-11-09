<#
.SYNOPSIS
    Private DNS Zone cross-subscription migration harness.
    Wraps THREE phases as discrete functions under one orchestrator:
      1. Export  - capture current zone state (records + links + PE map) to JSON
      2. Import  - recreate zone + records in TARGET subscription
      3. Relink  - reassociate each Private Endpoint's DNS zone group to the new zone
                   (restores automatic record lifecycle management)

.DESCRIPTION
    Phases are run INDIVIDUALLY and intentionally gated. You should validate
    DNS resolution between Import and Relink. Supports -DryRun on every phase.

.EXAMPLE
    # Phase 1 - safe, read-only
    .\Migrate-PrivateDns.ps1 -Phase Export -SourceSubscriptionId $src -ZoneName $zone -SourceResourceGroup $srg

.EXAMPLE
    # Phase 2 - additive
    .\Migrate-PrivateDns.ps1 -Phase Import -TargetSubscriptionId $tgt -TargetResourceGroup $trg -ZoneName $zone

.EXAMPLE
    # Phase 3 - HIGH IMPACT (dry-run first!)
    .\Migrate-PrivateDns.ps1 -Phase Relink -SourceSubscriptionId $src -TargetSubscriptionId $tgt `
        -TargetResourceGroup $trg -ZoneName $zone -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Export','Import','Relink')]
    [string]$Phase,

    [string]$SourceSubscriptionId,
    [string]$TargetSubscriptionId,
    [string]$SourceResourceGroup,
    [string]$TargetResourceGroup,

    [Parameter(Mandatory)]
    [string]$ZoneName,

    [string]$ArtifactFolder = ".\dns-migration\$ZoneName",

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# =====================================================================
# Shared Harness: logging, context switching, artifact paths
# =====================================================================
$script:RunId   = Get-Date -Format 'yyyyMMdd-HHmmss'
$null            = New-Item -ItemType Directory -Force -Path $ArtifactFolder
$script:LogFile  = Join-Path $ArtifactFolder "migration-$Phase-$RunId.log"
$RecordsFile     = Join-Path $ArtifactFolder 'records.json'
$LinksFile       = Join-Path $ArtifactFolder 'vnetlinks.json'
$PeMapFile       = Join-Path $ArtifactFolder 'pe-zonegroup-map.json'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK')]$Level='INFO')
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 's'), $Level, $Message
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line
}

function Set-Sub {
    param([string]$SubId)
    if (-not $SubId) { throw "Subscription Id required for phase '$Phase'." }
    Set-AzContext -SubscriptionId $SubId | Out-Null
    Write-Log "Context set to subscription $SubId"
}

if ($DryRun) { Write-Log "DRY RUN ENABLED - no writes will occur." WARN }

# =====================================================================
# FUNCTION 1 — EXPORT (read-only, always safe)
# =====================================================================
function Invoke-ExportPhase {
    Set-Sub $SourceSubscriptionId
    Write-Log "=== PHASE 1: EXPORT zone '$ZoneName' from RG '$SourceResourceGroup' ==="

    # --- Record sets (exclude Azure-managed SOA/NS) ---
    $records = Get-AzPrivateDnsRecordSet `
        -ResourceGroupName $SourceResourceGroup `
        -ZoneName $ZoneName |
        Where-Object { $_.RecordType -notin @('SOA','NS') }

    $records |
        Select-Object Name, RecordType, Ttl, Records |
        ConvertTo-Json -Depth 20 |
        Out-File $RecordsFile
    Write-Log ("Captured {0} record sets -> {1}" -f $records.Count, $RecordsFile) OK

    # --- VNet links ---
    $links = Get-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $SourceResourceGroup `
        -ZoneName $ZoneName

    $links |
        Select-Object Name, @{n='VnetId';e={$_.VirtualNetworkId}}, RegistrationEnabled |
        ConvertTo-Json -Depth 10 |
        Out-File $LinksFile
    Write-Log ("Captured {0} VNet links -> {1}" -f $links.Count, $LinksFile) OK

    # --- PE -> zone group map (critical for phase 3) ---
    $sourceZoneId = "/subscriptions/$SourceSubscriptionId/resourceGroups/$SourceResourceGroup/providers/Microsoft.Network/privateDnsZones/$ZoneName"
    $peMap = New-Object System.Collections.Generic.List[object]

    foreach ($pe in (Get-AzPrivateEndpoint)) {
        try {
            $zgs = Get-AzPrivateDnsZoneGroup `
                -ResourceGroupName $pe.ResourceGroupName `
                -PrivateEndpointName $pe.Name -ErrorAction Stop
        } catch { continue }

        foreach ($zg in $zgs) {
            foreach ($cfg in $zg.PrivateDnsZoneConfigs) {
                if ($cfg.PrivateDnsZoneId -ieq $sourceZoneId) {
                    $peMap.Add([PSCustomObject]@{
                        PrivateEndpoint = $pe.Name
                        ResourceGroup   = $pe.ResourceGroupName
                        ZoneGroupName   = $zg.Name
                        ConfigName      = $cfg.Name
                        CurrentZoneId   = $cfg.PrivateDnsZoneId
                    })
                }
            }
        }
    }

    $peMap | ConvertTo-Json -Depth 10 | Out-File $PeMapFile
    Write-Log ("Mapped {0} PE zone-group configs bound to this zone -> {1}" -f $peMap.Count, $PeMapFile) OK
    Write-Log "EXPORT complete. Review artifacts before importing." OK
}

# =====================================================================
# FUNCTION 2 — IMPORT (additive; recreates zone + records in target)
# =====================================================================
function Invoke-ImportPhase {
    if (-not (Test-Path $RecordsFile)) { throw "Missing $RecordsFile. Run Export first." }
    Set-Sub $TargetSubscriptionId
    Write-Log "=== PHASE 2: IMPORT zone '$ZoneName' into RG '$TargetResourceGroup' ==="

    # --- Ensure zone exists in target ---
    $zone = Get-AzPrivateDnsZone -ResourceGroupName $TargetResourceGroup -Name $ZoneName -ErrorAction SilentlyContinue
    if (-not $zone) {
        if ($DryRun) { Write-Log "[DRY RUN] Would create zone '$ZoneName'." WARN }
        else {
            New-AzPrivateDnsZone -ResourceGroupName $TargetResourceGroup -Name $ZoneName | Out-Null
            Write-Log "Created zone '$ZoneName' in target." OK
        }
    } else { Write-Log "Zone '$ZoneName' already exists in target. Records will be merged." WARN }

    # --- Recreate record sets ---
    $records = Get-Content $RecordsFile -Raw | ConvertFrom-Json
    foreach ($r in $records) {
        $configs = switch ($r.RecordType) {
            'A'     { $r.Records | ForEach-Object { New-AzPrivateDnsRecordConfig -Ipv4Address $_.Ipv4Address } }
            'AAAA'  { $r.Records | ForEach-Object { New-AzPrivateDnsRecordConfig -Ipv6Address $_.Ipv6Address } }
            'CNAME' { $r.Records | ForEach-Object { New-AzPrivateDnsRecordConfig -Cname $_.Cname } }
            'TXT'   { $r.Records | ForEach-Object { New-AzPrivateDnsRecordConfig -Value $_.Value } }
            default { Write-Log "Skipping unsupported type $($r.RecordType) for $($r.Name)" WARN; $null }
        }
        if (-not $configs) { continue }

        if ($DryRun) {
            Write-Log ("[DRY RUN] Would create {0} '{1}' (TTL {2})" -f $r.RecordType, $r.Name, $r.Ttl) WARN
        } else {
            New-AzPrivateDnsRecordSet `
                -ResourceGroupName $TargetResourceGroup `
                -ZoneName $ZoneName `
                -Name $r.Name `
                -RecordType $r.RecordType `
                -Ttl $r.Ttl `
                -PrivateDnsRecord $configs `
                -Overwrite -ErrorAction Stop | Out-Null
            Write-Log ("Created {0} '{1}'" -f $r.RecordType, $r.Name) OK
        }
    }

    # --- Recreate VNet links ---
    if (Test-Path $LinksFile) {
        $links = Get-Content $LinksFile -Raw | ConvertFrom-Json
        foreach ($l in $links) {
            if ($DryRun) { Write-Log "[DRY RUN] Would create VNet link '$($l.Name)'." WARN; continue }
            New-AzPrivateDnsVirtualNetworkLink `
                -ResourceGroupName $TargetResourceGroup `
                -ZoneName $ZoneName `
                -Name $l.Name `
                -VirtualNetworkId $l.VnetId `
                -EnableRegistration:$l.RegistrationEnabled -ErrorAction Stop | Out-Null
            Write-Log ("Created VNet link '{0}'" -f $l.Name) OK
        }
    }

    Write-Log "IMPORT complete. >>> VALIDATE RESOLUTION NOW before running Relink. <<<" OK
}

# =====================================================================
# FUNCTION 3 — RELINK (HIGH IMPACT: reassociates PE zone groups)
# =====================================================================
function Invoke-RelinkPhase {
    if (-not (Test-Path $PeMapFile)) { throw "Missing $PeMapFile. Run Export first." }
    $targetZoneId = "/subscriptions/$TargetSubscriptionId/resourceGroups/$TargetResourceGroup/providers/Microsoft.Network/privateDnsZones/$ZoneName"

    Write-Log "=== PHASE 3: RELINK PE zone groups -> $targetZoneId ==="
    Write-Log "This rewrites live PE A-records and restores lifecycle management." WARN

    $peMap = Get-Content $PeMapFile -Raw | ConvertFrom-Json
    Set-Sub $SourceSubscriptionId   # PEs typically live where they were created

    $summary = New-Object System.Collections.Generic.List[object]

    foreach ($pe in $peMap) {
        Write-Log ("PE '{0}' (RG {1}) zoneGroup '{2}'" -f $pe.PrivateEndpoint, $pe.ResourceGroup, $pe.ZoneGroupName)

        $newConfig = New-AzPrivateDnsZoneConfig `
            -Name $pe.ConfigName `
            -PrivateDnsZoneId $targetZoneId

        if ($DryRun) {
            Write-Log ("  [DRY RUN] Would repoint '{0}' -> target zone." -f $pe.ConfigName) WARN
            $summary.Add([PSCustomObject]@{ PE=$pe.PrivateEndpoint; Action='DRYRUN' })
            continue
        }

        try {
            Set-AzPrivateDnsZoneGroup `
                -ResourceGroupName $pe.ResourceGroup `
                -PrivateEndpointName $pe.PrivateEndpoint `
                -Name $pe.ZoneGroupName `
                -PrivateDnsZoneConfig $newConfig -ErrorAction Stop | Out-Null
            Write-Log ("  Repointed '{0}' to target zone." -f $pe.PrivateEndpoint) OK
            $summary.Add([PSCustomObject]@{ PE=$pe.PrivateEndpoint; Action='REPOINTED' })
        }
        catch {
            Write-Log ("  FAILED '{0}': {1}" -f $pe.PrivateEndpoint, $_.Exception.Message) ERROR
            $summary.Add([PSCustomObject]@{ PE=$pe.PrivateEndpoint; Action='FAILED' })
        }
    }

    Write-Log "----- RELINK SUMMARY -----"
    $summary | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_ }
    Write-Log "RELINK complete. Validate auto-management, then remove old zone after TTL." OK
}

# =====================================================================
# Orchestrator
# =====================================================================
switch ($Phase) {
    'Export' { Invoke-ExportPhase }
    'Import' { Invoke-ImportPhase }
    'Relink' { Invoke-RelinkPhase }
}

Write-Log ("Phase '{0}' finished. Log: {1}" -f $Phase, $script:LogFile)