// =============================================================================
// Network Module
// =============================================================================
// The virtual network the cluster's nodes and the database share, the private DNS
// zone the database is found through, and the public IP address the site is served on.
// =============================================================================

@description('The name of the virtual network')
param virtualNetworkName string

@description('The name of the public IP address the gateway serves the site on')
param publicIpName string

@description('DNS label for the public IP: the site is <label>.<region>.cloudapp.azure.com')
param dnsLabel string

@description('The Azure region where the resources will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.10.0.0/16']
    }
    subnets: [
      {
        // Nodes only: pods get addresses from the cluster's own overlay range
        name: 'nodes'
        properties: {
          addressPrefix: '10.10.0.0/22'
        }
      }
      {
        name: 'postgres'
        properties: {
          addressPrefix: '10.10.4.0/28'
          delegations: [
            {
              name: 'postgres'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// The flexible server registers its private address here, and the nodes resolve it from here
resource postgresDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${dnsLabel}.private.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource postgresDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: postgresDnsZone
  name: virtualNetworkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// Owned here rather than by the cluster, so the address and its name survive the
// cluster being stopped, upgraded or rebuilt.
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsLabel
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the virtual network')
output virtualNetworkName string = virtualNetwork.name

@description('The resource ID of the subnet for cluster nodes')
output nodeSubnetId string = virtualNetwork.properties.subnets[0].id

@description('The resource ID of the subnet delegated to PostgreSQL')
output postgresSubnetId string = virtualNetwork.properties.subnets[1].id

@description('The resource ID of the private DNS zone for PostgreSQL')
output postgresDnsZoneId string = postgresDnsZone.id

@description('The name of the public IP address')
output publicIpName string = publicIp.name

@description('The DNS name of the public IP address')
output hostName string = publicIp.properties.dnsSettings.fqdn
