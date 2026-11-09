# 1. Export from source
.\exportPrivateDnsZones.ps1 -SourceSubscriptionId "<src-sub-id>" -OutputFile dns-export.json

# 2. Review dns-export.json, then import to target
Import-PrivateDnsZones -InputFile dns-export.json `
    -TargetSubscriptionId "<tgt-sub-id>" `
    -TargetResourceGroupName "rg-dns-new" `
    -VNetIdMap @{
        '/subscriptions/<src>/...virtualNetworks/vnet1' = '/subscriptions/<tgt>/...virtualNetworks/vnet1'
    }