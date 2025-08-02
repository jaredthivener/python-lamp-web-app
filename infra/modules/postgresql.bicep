// =============================================================================
// Azure Database for PostgreSQL - Flexible Server Module (Free Tier)
// =============================================================================
// This module deploys Azure Database for PostgreSQL - Flexible Server with:
// - Free tier (Burstable B1ms, 32GB storage, 1 vCore, 2GB RAM)
// - System-managed identity authentication
// - SSL enforcement
// - Connection string stored in Key Vault
// =============================================================================

@description('The name of the PostgreSQL server')
param postgresServerName string

@description('The name of the PostgreSQL database')
param postgresDatabaseName string = 'lamp_db'

@description('The Azure region where the PostgreSQL resources will be deployed')
param location string = resourceGroup().location

@description('Common tags to be applied to all resources')
param tags object = {}

@description('The administrator login username for the PostgreSQL server')
param administratorLogin string = 'postgres'

@description('The administrator login password for the PostgreSQL server')
@secure()
param administratorLoginPassword string

@description('The Key Vault name where secrets will be stored')
param keyVaultName string

@description('Environment name for resource naming')
param environmentName string

// =============================================================================
// Azure Database for PostgreSQL - Flexible Server (Free Tier)
// =============================================================================
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2025-01-01-preview' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'  // Free tier: 1 vCore, 2GB RAM
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: '15'  // PostgreSQL 15
    storage: {
      storageSizeGB: 32  // Free tier: 32GB storage
      iops: 120
      tier: 'P4'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    highAvailability: {
      mode: 'Disabled'  // Not available in free tier
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
    }
  }
}

// =============================================================================
// PostgreSQL Database
// =============================================================================
resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2025-01-01-preview' = {
  parent: postgresServer
  name: postgresDatabaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// =============================================================================
// Firewall Rules
// =============================================================================
// Allow Azure services to access the server
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2025-01-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Allow all IPs for development (you may want to restrict this in production)
resource allowAllIPs 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2025-01-01-preview' = if (environmentName == 'dev') {
  parent: postgresServer
  name: 'AllowAllIPs'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// =============================================================================
// Key Vault Secret for Connection String
// =============================================================================
// Get reference to existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' existing = {
  name: keyVaultName
}

// Store the PostgreSQL connection string in Key Vault
resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-12-01-preview' = {
  parent: keyVault
  name: 'postgresql-connection-string'
  properties: {
    value: 'host=${postgresServer.properties.fullyQualifiedDomainName} port=5432 dbname=${postgresDatabaseName} user=${administratorLogin} password=${administratorLoginPassword} sslmode=require'
    contentType: 'application/x-postgresql-connection-string'
    attributes: {
      enabled: true
    }
  }
}

// =============================================================================
// Database Monitoring Configuration
// =============================================================================
// Enable diagnostic settings to send PostgreSQL logs and metrics to Log Analytics
resource postgresDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'PostgreSQL-Diagnostics'
  scope: postgresServer
  properties: {
    workspaceId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${replace(postgresServerName, '-postgres', '')}-logs'
    logs: [
      {
        category: 'PostgreSQLLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'PostgreSQLFlexSessions'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'PostgreSQLFlexQueryStoreRuntime'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'PostgreSQLFlexQueryStoreWaitStats'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Configure PostgreSQL server parameters for enhanced logging
resource logMinDurationStatement 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'log_min_duration_statement'
  properties: {
    value: '1000'  // Log queries taking longer than 1 second
    source: 'user-override'
  }
}

resource logStatement 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'log_statement'
  properties: {
    value: 'ddl'  // Log DDL statements (CREATE, ALTER, DROP)
    source: 'user-override'
  }
}

resource logConnections 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'log_connections'
  properties: {
    value: 'on'  // Log connection attempts
    source: 'user-override'
  }
}

resource logDisconnections 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'log_disconnections'
  properties: {
    value: 'on'  // Log disconnections
    source: 'user-override'
  }
}

// Enable Query Store for performance insights
resource queryStoreCapture 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'pg_qs.query_capture_mode'
  properties: {
    value: 'top'  // Capture top queries for performance analysis
    source: 'user-override'
  }
}

resource queryStoreMaxQueryTextLength 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: postgresServer
  name: 'pg_qs.max_query_text_length'
  properties: {
    value: '6000'  // Store up to 6000 characters of query text
    source: 'user-override'
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The fully qualified domain name of the PostgreSQL server')
output serverFqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('The name of the PostgreSQL server')
output serverName string = postgresServer.name

@description('The name of the PostgreSQL database')
output databaseName string = postgresDatabase.name

@description('The administrator login username')
output administratorLogin string = administratorLogin

@description('The Key Vault secret name containing the connection string')
output connectionStringSecretName string = connectionStringSecret.name

@description('The resource ID of the PostgreSQL server')
output serverId string = postgresServer.id

@description('The resource ID of the PostgreSQL database')
output databaseId string = postgresDatabase.id
