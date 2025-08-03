// =============================================================================
// Container Registry Webhook Module
// =============================================================================
// This module creates a webhook for continuous deployment after both ACR and
// App Service are created, avoiding circular dependencies
// =============================================================================

@description('The name of the Container Registry')
param containerRegistryName string

@description('The Azure region where resources will be deployed')
param location string

@description('Tags to apply to the webhook')
param tags object = {}

@description('The service URI for the webhook')
@secure()
param webhookServiceUri string

@description('The name of the Docker image to watch')
param imageName string = 'lamp-app'

// =============================================================================
// Get existing Container Registry
// =============================================================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

// =============================================================================
// Container Registry Webhook for Continuous Deployment
// =============================================================================
resource containerRegistryWebhook 'Microsoft.ContainerRegistry/registries/webhooks@2023-07-01' = {
  name: 'lampappwebhook'
  parent: containerRegistry
  location: location
  tags: tags
  properties: {
    serviceUri: webhookServiceUri
    actions: ['push']
    scope: '${imageName}:*'
    status: 'enabled'
    customHeaders: {
      'Content-Type': 'application/json'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the webhook')
output webhookName string = containerRegistryWebhook.name

@description('The resource ID of the webhook')
output webhookId string = containerRegistryWebhook.id
