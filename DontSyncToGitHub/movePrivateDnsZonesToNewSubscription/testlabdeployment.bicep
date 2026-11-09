//=====================================================================
//  Private DNS Zone migration LAB repro (SOURCE side)
//  Deploys: VNet + Private DNS zone + 2 storage PEs (2 managed A-records)
//           + manual A-record + optional KeyVault zone + optional test VM
//  Scope:   resourceGroup
//=====================================================================
targetScope = 'resourceGroup'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Short prefix for resource names (lowercase, <= 8 chars).')
@maxLength(8)
param namePrefix string = 'pdnslab'

@description('Deploy a second zone (Key Vault) to test zone isolation.')
param deploySecondZone bool = false

@description('Deploy a Windows test VM for Resolve-DnsName checks.')
param deployTestVm bool = true

@description('Admin username for the test VM.')
param adminUsername string = 'ken'

@description('Admin password for the test VM.')
@secure()
param adminPassword string = 'Pa$$w0rd'

@description('Source IP\'s to allow to connect to the public IP of the test VM.')
param sourceIp string = '32.216.226.40'

// Deterministic, globally-unique storage names
var suffix    = uniqueString(resourceGroup().id)
var sa1Name   = toLower('${namePrefix}sa1${substring(suffix, 0, 6)}')
var sa2Name   = toLower('${namePrefix}sa2${substring(suffix, 0, 6)}')
var kvName    = toLower('${namePrefix}kv1${substring(suffix, 0, 7)}')

var blobZoneName  = 'privatelink.blob.${environment().suffixes.storage}'
var kvZoneName    = 'privatelink.vaultcore.azure.net'

//---------------------------------------------------------------------
// Networking
//---------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.50.0.0/16' ] }
    subnets: [
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.50.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-vm'
        properties: { addressPrefix: '10.50.2.0/24' }
      }
    ]
  }
}

//---------------------------------------------------------------------
// Private DNS zone (blob) + VNet link
//---------------------------------------------------------------------
resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: blobZoneName
  location: 'global'
}

resource blobZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobZone
  name: '${namePrefix}-blob-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// Manual (non-PE) A-record — should survive the Move untouched
resource manualRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: blobZone
  name: 'manual-static-test'
  properties: {
    ttl: 300
    aRecords: [ { ipv4Address: '10.50.99.99' } ]
  }
}

//---------------------------------------------------------------------
// Storage account #1 + blob private endpoint + DNS zone group
//---------------------------------------------------------------------
resource sa1 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: sa1Name
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource pe1 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${namePrefix}-sa1-pe'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/snet-pe' }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-sa1-plsc'
        properties: {
          privateLinkServiceId: sa1.id
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}

resource pe1ZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: pe1
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-blob'
        properties: { privateDnsZoneId: blobZone.id }
      }
    ]
  }
}

//---------------------------------------------------------------------
// Storage account #2 + blob private endpoint + DNS zone group
//---------------------------------------------------------------------
resource sa2 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: sa2Name
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource pe2 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${namePrefix}-sa2-pe'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/snet-pe' }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-sa2-plsc'
        properties: {
          privateLinkServiceId: sa2.id
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}

resource pe2ZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: pe2
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-blob'
        properties: { privateDnsZoneId: blobZone.id }
      }
    ]
  }
}

//---------------------------------------------------------------------
// OPTIONAL: second zone (Key Vault) to confirm sweep isolation
//---------------------------------------------------------------------
resource kvZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deploySecondZone) {
  name: kvZoneName
  location: 'global'
}

resource kvZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deploySecondZone) {
  parent: kvZone
  name: '${namePrefix}-kv-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = if (deploySecondZone) {
  name: kvName
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
  }
}

resource kvPe 'Microsoft.Network/privateEndpoints@2023-09-01' = if (deploySecondZone) {
  name: '${namePrefix}-kv-pe'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/snet-pe' }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-kv-plsc'
        properties: {
          privateLinkServiceId: kv.id
          groupIds: [ 'vault' ]
        }
      }
    ]
  }
}

resource kvPeZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (deploySecondZone) {
  parent: kvPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-vault'
        properties: { privateDnsZoneId: kvZone.id }
      }
    ]
  }
}

//---------------------------------------------------------------------
// OPTIONAL: Windows test VM (Resolve-DnsName host)
//---------------------------------------------------------------------
resource vmNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = if (deployTestVm) {
  name: '${namePrefix}-vm-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: sourceIp   // <-- TIGHTEN to your IP before use
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vmPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (deployTestVm) {
  name: '${namePrefix}-vm-pip'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = if (deployTestVm) {
  name: '${namePrefix}-vm-nic'
  location: location
  properties: {
    networkSecurityGroup: { id: vmNsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: '${vnet.id}/subnets/snet-vm' }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: vmPip.id }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = if (deployTestVm) {
  name: '${namePrefix}-vm'
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: 'pdnslabvm'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: { createOption: 'FromImage', managedDisk: { storageAccountType: 'StandardSSD_LRS' } }
    }
    networkProfile: { networkInterfaces: [ { id: vmNic.id } ] }
  }
}

//---------------------------------------------------------------------
// Outputs — everything the test plan + relink script needs
//---------------------------------------------------------------------
output sourceSubscriptionId string = subscription().subscriptionId
output sourceResourceGroup  string = resourceGroup().name
output blobZoneName         string = blobZoneName
output storage1Fqdn         string = '${sa1Name}.privatelink.blob.${environment().suffixes.storage}'
output storage2Fqdn         string = '${sa2Name}.privatelink.blob.${environment().suffixes.storage}'
output peNames              array  = [ '${namePrefix}-sa1-pe', '${namePrefix}-sa2-pe' ]
output testVmPublicIp       string = deployTestVm ? vmPip.properties.ipAddress : 'not-deployed'
