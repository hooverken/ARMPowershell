<#
.SYNOPSIS
    Exports Azure Private DNS zones (records + VNet links) from a source subscription
    so they can be recreated in a target subscription.

.DESCRIPTION
    Connects to a source subscription, enumerates all Private DNS zones in a resource
    group (or across the whole subscription), exports every record set and virtual
    network link, and writes the result to a JSON file.  A companion Import function
    reads that file and recreates the zones, records, and links in the target subscription.

.PARAMETER SourceSubscriptionId
    The subscription ID that currently owns the Private DNS zones.

.PARAMETER ResourceGroupName
    Optional. Limit the export to zones in a specific resource group.
    If omitted, all Private DNS zones in the subscription are exported.

.PARAMETER OutputFile
    Path for the exported JSON file.  Defaults to .\PrivateDnsExport.json.

.EXAMPLE
    # Export all zones in a subscription
    .\exportPrivateDnsZones.ps1 -SourceSubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.EXAMPLE
    # Export zones from a specific resource group
    .\exportPrivateDnsZones.ps1 -SourceSubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ResourceGroupName "rg-dns" -OutputFile "C:\Temp\dns-export.json"

.NOTES
    Requires: Az.Accounts, Az.PrivateDns
    To import on the target subscription run Import-PrivateDnsZones (defined at the
    bottom of this file).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$SourceSubscriptionId,
    [Parameter()][string]$ResourceGroupName,
    [Parameter()][string]$OutputFile = '.\PrivateDnsExport.json'
)

#region ── Helpers ────────────────────────────────────────────────────────────

function Get-RequiredModules {
    $required = @('Az.Accounts', 'Az.PrivateDns')
    foreach ($mod in $required) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Error "Required module '$mod' is not installed. Run: Install-Module $mod"
            exit 1
        }
    }
}

function ConvertTo-ExportableRecordSet {
    param ([Microsoft.Azure.Commands.PrivateDns.Models.PSPrivateDnsRecordSet]$RecordSet)

    # Serialize each record type into a plain hashtable so the output JSON is portable
    $records = foreach ($r in $RecordSet.Records) {
        switch ($RecordSet.RecordType) {
            'A'     { @{ Type = 'A';     Ipv4Address    = $r.Ipv4Address } }
            'AAAA'  { @{ Type = 'AAAA';  Ipv6Address    = $r.Ipv6Address } }
            'CNAME' { @{ Type = 'CNAME'; Cname          = $r.Cname } }
            'MX'    { @{ Type = 'MX';    Preference     = $r.Preference; Exchange = $r.Exchange } }
            'PTR'   { @{ Type = 'PTR';   Ptrdname       = $r.Ptrdname } }
            'SRV'   { @{ Type = 'SRV';   Priority       = $r.Priority; Weight = $r.Weight; Port = $r.Port; Target = $r.Target } }
            'TXT'   { @{ Type = 'TXT';   Value          = $r.Value } }
            default { $null }
        }
    }

    return [pscustomobject]@{
        Name       = $RecordSet.Name
        RecordType = $RecordSet.RecordType.ToString()
        Ttl        = $RecordSet.Ttl
        Metadata   = $RecordSet.Metadata
        Records    = @($records | Where-Object { $_ })
    }
}

#endregion

#region ── Export ─────────────────────────────────────────────────────────────

Get-RequiredModules

# Ensure we are connected and targeting the right subscription
Write-Host "Setting context to subscription: $SourceSubscriptionId"
$null = Set-AzContext -SubscriptionId $SourceSubscriptionId -ErrorAction Stop

# Collect zones
if ($ResourceGroupName) {
    Write-Host "Enumerating Private DNS zones in resource group: $ResourceGroupName"
    $zones = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName
} else {
    Write-Host "Enumerating all Private DNS zones in subscription: $SourceSubscriptionId"
    $zones = Get-AzPrivateDnsZone
}

if (-not $zones) {
    Write-Warning "No Private DNS zones found. Nothing to export."
    exit 0
}

$export = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($zone in $zones) {
    Write-Host "  Exporting zone: $($zone.Name)  [$($zone.ResourceGroupName)]"

    # Record sets (skip the SOA record – it is auto-created)
    $recordSets = Get-AzPrivateDnsRecordSet -ZoneName $zone.Name `
                      -ResourceGroupName $zone.ResourceGroupName |
                  Where-Object { $_.RecordType -ne 'SOA' }

    $exportedRecords = foreach ($rs in $recordSets) {
        ConvertTo-ExportableRecordSet -RecordSet $rs
    }

    # Virtual network links
    $links = Get-AzPrivateDnsVirtualNetworkLink -ZoneName $zone.Name `
                 -ResourceGroupName $zone.ResourceGroupName

    $exportedLinks = foreach ($link in $links) {
        [pscustomobject]@{
            Name                 = $link.Name
            VirtualNetworkId     = $link.VirtualNetworkId   # caller maps this to target VNet
            RegistrationEnabled  = $link.RegistrationEnabled
        }
    }

    $export.Add([pscustomobject]@{
        ZoneName          = $zone.Name
        ResourceGroupName = $zone.ResourceGroupName
        Tags              = $zone.Tags
        RecordSets        = @($exportedRecords)
        VirtualNetworkLinks = @($exportedLinks)
    })
}

$export | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "`nExport complete. File saved to: $((Resolve-Path $OutputFile).Path)" -ForegroundColor Green
Write-Host "Zones exported: $($export.Count)"

#endregion