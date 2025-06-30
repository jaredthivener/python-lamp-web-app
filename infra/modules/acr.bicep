// =============================================================================
// Azure Container Registry Module
// =============================================================================
// This module creates an Azure Container Registry with security best practices
// =============================================================================

@description('The name of the container registry')
param containerRegistryName string

@description('The Azure region where the registry will be deployed')
param location string

@description('The SKU for the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param containerRegistrySku string = 'Basic'

@description('Tags to apply to the container registry')
param tags object = {}

// =============================================================================
// Azure Container Registry
// =============================================================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: false
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Container Registry')
output containerRegistryName string = containerRegistry.name

@description('The login server of the Container Registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The resource ID of the Container Registry')
output containerRegistryId string = containerRegistry.id

@description('The resource object of the Container Registry')
output containerRegistry object = containerRegistry
