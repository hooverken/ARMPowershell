#region ── Import (run separately against the target subscription) ────────────

<#
.SYNOPSIS
    Recreates Private DNS zones exported by this script in a target subscription.

.DESCRIPTION
    Call Import-PrivateDnsZones after authenticating to the target subscription.
    VNet links are skipped unless you supply a -VNetIdMap hashtable that translates
    source VNet resource IDs to target VNet resource IDs.

.PARAMETER InputFile
    Path to the JSON file produced by the export script.

.PARAMETER TargetSubscriptionId
    The subscription to import into.

.PARAMETER TargetResourceGroupName
    The resource group in the target subscription where zones will be created.
    The resource group must already exist.

.PARAMETER VNetIdMap
    Optional hashtable mapping source VNet IDs to target VNet IDs, e.g.:
    @{ '/subscriptions/src.../virtualNetworks/vnet1' = '/subscriptions/tgt.../virtualNetworks/vnet1' }
    Links whose source VNet ID has no mapping are skipped with a warning.

.EXAMPLE
    Import-PrivateDnsZones -InputFile ".\PrivateDnsExport.json" `
        -TargetSubscriptionId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -TargetResourceGroupName "rg-dns-new" `
        -VNetIdMap @{ '<sourceVNetId>' = '<targetVNetId>' }
#>

function Import-PrivateDnsZones {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$InputFile,

        [Parameter(Mandatory)]
        [string]$TargetSubscriptionId,

        [Parameter(Mandatory)]
        [string]$TargetResourceGroupName,

        [Parameter()]
        [hashtable]$VNetIdMap = @{}
    )

    Get-RequiredModules

    Write-Host "Setting context to target subscription: $TargetSubscriptionId"
    $null = Set-AzContext -SubscriptionId $TargetSubscriptionId -ErrorAction Stop

    $data = Get-Content -Path $InputFile -Raw | ConvertFrom-Json

    foreach ($zone in $data) {
        Write-Host "`nImporting zone: $($zone.ZoneName)"

        # Create the zone (idempotent – skip if already exists)
        $existingZone = Get-AzPrivateDnsZone -ResourceGroupName $TargetResourceGroupName `
                            -Name $zone.ZoneName -ErrorAction SilentlyContinue
        if ($existingZone) {
            Write-Host "  Zone already exists – skipping creation."
        } else {
            if ($PSCmdlet.ShouldProcess($zone.ZoneName, 'Create Private DNS Zone')) {
                $null = New-AzPrivateDnsZone -ResourceGroupName $TargetResourceGroupName `
                            -Name $zone.ZoneName -Tag ($zone.Tags ?? @{})
                Write-Host "  Zone created."
            }
        }

        # Recreate record sets
        foreach ($rs in $zone.RecordSets) {
            if ($rs.RecordType -in @('SOA', 'NS') -and $rs.Name -eq '@') { continue }

            Write-Host "  Record set: $($rs.RecordType) $($rs.Name)"

            # Build the record objects
            $recordObjects = foreach ($r in $rs.Records) {
                switch ($r.Type) {
                    'A'     { New-AzPrivateDnsRecordConfig -Ipv4Address $r.Ipv4Address }
                    'AAAA'  { New-AzPrivateDnsRecordConfig -Ipv6Address $r.Ipv6Address }
                    'CNAME' { New-AzPrivateDnsRecordConfig -Cname $r.Cname }
                    'MX'    { New-AzPrivateDnsRecordConfig -Preference $r.Preference -Exchange $r.Exchange }
                    'PTR'   { New-AzPrivateDnsRecordConfig -Ptrdname $r.Ptrdname }
                    'SRV'   { New-AzPrivateDnsRecordConfig -Priority $r.Priority -Weight $r.Weight `
                                  -Port $r.Port -Target $r.Target }
                    'TXT'   { New-AzPrivateDnsRecordConfig -Value $r.Value }
                }
            }

            if ($PSCmdlet.ShouldProcess("$($rs.RecordType) $($rs.Name)", 'Create Record Set')) {
                $null = New-AzPrivateDnsRecordSet -ZoneName $zone.ZoneName `
                            -ResourceGroupName $TargetResourceGroupName `
                            -Name $rs.Name -RecordType $rs.RecordType -Ttl $rs.Ttl `
                            -PrivateDnsRecords $recordObjects -Overwrite
            }
        }

        # Recreate VNet links (only if caller supplied a mapping)
        foreach ($link in $zone.VirtualNetworkLinks) {
            if (-not $VNetIdMap.ContainsKey($link.VirtualNetworkId)) {
                Write-Warning "  No target VNet mapping for '$($link.VirtualNetworkId)' – skipping link '$($link.Name)'."
                continue
            }

            $targetVNetId = $VNetIdMap[$link.VirtualNetworkId]
            Write-Host "  VNet link: $($link.Name) -> $targetVNetId"

            if ($PSCmdlet.ShouldProcess($link.Name, 'Create VNet Link')) {
                $null = New-AzPrivateDnsVirtualNetworkLink -ZoneName $zone.ZoneName `
                            -ResourceGroupName $TargetResourceGroupName `
                            -Name $link.Name -VirtualNetworkId $targetVNetId `
                            -EnableRegistration:$link.RegistrationEnabled
            }
        }
    }

    Write-Host "`nImport complete." -ForegroundColor Green
}

#endregion
