// =============================================================================
// Managed Identity Module
// =============================================================================
// This module creates a user-assigned managed identity that can be used
// by the App Service for ACR authentication and other Azure resource access
// =============================================================================

@description('The name of the managed identity')
param managedIdentityName string

@description('The Azure region where the managed identity will be deployed')
param location string

@description('Tags to apply to the managed identity')
param tags object = {}

// =============================================================================
// User-Assigned Managed Identity
// =============================================================================
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the managed identity')
output managedIdentityName string = managedIdentity.name

@description('The resource ID of the managed identity')
output managedIdentityId string = managedIdentity.id

@description('The principal ID of the managed identity')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The client ID of the managed identity')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('The managed identity resource object')
output managedIdentity object = managedIdentity
