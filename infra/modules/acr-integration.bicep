// =============================================================================
// ACR Integration Module
// =============================================================================
// This module handles the integration between ACR and App Service
// including role assignments and webhooks
// =============================================================================

@description('The resource ID of the Container Registry')
param containerRegistryId string

@description('The name of the Container Registry')
param containerRegistryName string

@description('The principal ID of the App Service managed identity')
param appServicePrincipalId string

@description('The service URI for the webhook')
@secure()
param webhookServiceUri string

@description('The Azure region where resources will be deployed')
param location string

// Reference to existing container registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' existing = {
  name: containerRegistryName
}

// =============================================================================
// Role Assignment: Grant App Service AcrPull access to Container Registry
// =============================================================================
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistryId, appServicePrincipalId, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Container Registry Webhook for Continuous Deployment
// =============================================================================
resource containerRegistryWebhook 'Microsoft.ContainerRegistry/registries/webhooks@2025-05-01-preview' = {
  name: 'lampappwebhook'
  parent: containerRegistry
  location: location
  properties: {
    serviceUri: webhookServiceUri
    actions: ['push']
    scope: 'lamp-app:*'
    status: 'enabled'
    customHeaders: {
      'Content-Type': 'application/json'
    }
  }
  dependsOn: [
    acrPullRoleAssignment
  ]
}

// =============================================================================
// Outputs
// =============================================================================
@description('The resource ID of the role assignment')
output roleAssignmentId string = acrPullRoleAssignment.id

@description('The name of the webhook')
output webhookName string = containerRegistryWebhook.name
