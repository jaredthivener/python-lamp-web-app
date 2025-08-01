// =============================================================================
// Key Vault Module
// =============================================================================
// This module creates Azure Key Vault for secure storage of application secrets
// =============================================================================

@description('The name of the Key Vault')
param keyVaultName string

@description('The Azure region where the Key Vault will be deployed')
param location string

@description('Tags to apply to the Key Vault')
param tags object = {}

@description('The tenant ID for the Key Vault')
param tenantId string = tenant().tenantId

@description('Whether to enable Key Vault for template deployment')
param enabledForTemplateDeployment bool = true

@description('Whether to enable Key Vault for disk encryption')
param enabledForDiskEncryption bool = false

@description('Whether to enable Key Vault for deployment')
param enabledForDeployment bool = false

@description('The SKU for the Key Vault')
@allowed(['standard', 'premium'])
param skuName string = 'standard'

@description('Application Insights connection string to store as secret')
@secure()
param applicationInsightsConnectionString string

@description('Principal ID of the managed identity that needs access to Key Vault secrets')
param managedIdentityPrincipalId string

// =============================================================================
// Azure Key Vault
// =============================================================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: tenantId
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// =============================================================================
// Key Vault Secret for Application Insights Connection String
// =============================================================================
resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(applicationInsightsConnectionString)) {
  parent: keyVault
  name: 'ApplicationInsights--ConnectionString'
  properties: {
    value: applicationInsightsConnectionString
    contentType: 'text/plain'
  }
}

// =============================================================================
// Role Assignment: Grant Managed Identity Key Vault Secrets User access
// =============================================================================
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(managedIdentityPrincipalId)) {
  name: guid(keyVault.id, managedIdentityPrincipalId, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The Key Vault resource object')
output keyVault object = keyVault
