// =============================================================================
// Azure Database for PostgreSQL - Flexible Server Module
// =============================================================================
// - Burstable B1ms, 32 GB: the smallest server there is
// - Private: it has an address inside the virtual network and none on the internet
// - No passwords: the only way in is an Entra token, and the only principal allowed
//   is the managed identity the lamp pods run as
// =============================================================================

@description('The name of the PostgreSQL server')
param postgresServerName string

@description('The name of the PostgreSQL database')
param postgresDatabaseName string

@description('The Azure region where the PostgreSQL resources will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Resource ID of the subnet delegated to PostgreSQL flexible servers')
param delegatedSubnetId string

@description('Resource ID of the private DNS zone the server registers itself in')
param privateDnsZoneId string

@description('Object (principal) ID of the managed identity that administers the server')
param administratorPrincipalId string

@description('Name of that managed identity. It doubles as the PostgreSQL user name.')
param administratorPrincipalName string

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '18'
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: tenant().tenantId
    }
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresServer
  name: postgresDatabaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ponytail: the app signs in as the server's administrator. A second, least-privileged
// role takes SQL run from inside the network (pgaadauth_create_principal), which Bicep
// cannot do; add it when something other than the lamp shares this server.
resource postgresAdministrator 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: postgresServer
  name: administratorPrincipalId
  properties: {
    principalType: 'ServicePrincipal'
    principalName: administratorPrincipalName
    tenantId: tenant().tenantId
  }
  dependsOn: [
    postgresDatabase // the server only takes one change at a time
  ]
}

// =============================================================================
// Outputs
// =============================================================================
@description('The fully qualified domain name of the PostgreSQL server')
output serverFqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('The name of the PostgreSQL server')
output serverName string = postgresServer.name
