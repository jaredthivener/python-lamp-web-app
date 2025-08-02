targetScope = 'subscription'
// =============================================================================
// Azure Infrastructure for Lamp Web App - Main Template
// =============================================================================
// This Bicep template orchestrates the deployment of the lamp web app infrastructure
// using modular design for better maintainability and reusability.
//
// Architecture:
// - Monitoring module: Log Analytics workspace and Application Insights
// - App Service module: App Service Plan and App Service with container support
// - ACR module: Azure Container Registry with security and webhooks
//
// Security Features:
// - System-managed identity for secure ACR authentication
// - HTTPS-only access enforced
// - No admin credentials stored
// - Least privilege access (AcrPull role only)
// =============================================================================
@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = 'rg-python-webapp'

@description('The name of the environment (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string

@description('The Azure region where resources will be deployed')
@allowed(['centralus', 'eastus', 'eastus2', 'westus2', 'westeurope', 'northeurope', 'southeastasia'])
param location string = 'centralus'

@description('The SKU for the App Service Plan')
@allowed(['F1', 'D1', 'B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2', 'P1v3', 'P2v3', 'P3v3'])
param appServicePlanSku string = 'F1'

@description('The SKU for the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param containerRegistrySku string = 'Basic'

@description('The port number the application listens on')
param appPort string = '8000'

@description('The Git repository URL containing the source code and Dockerfile')
param sourceRepositoryUrl string = 'https://github.com/jaredthivener/python-lamp-web-app'

@description('The Git branch to use for building the image')
param sourceBranch string = 'main'

@description('The name of the Docker image to build')
param imageName string = 'lamp-app'

@description('The tag for the Docker image')
param imageTag string = 'latest'

@description('The path to the Dockerfile relative to the repository root')
param dockerfilePath string = 'Dockerfile'

// Generate unique resource names using resource token
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var resourcePrefix = 'lamp'

// Resource names following Azure naming conventions
var containerRegistryName = '${resourcePrefix}acr${resourceToken}'
var appServicePlanName = '${resourcePrefix}-plan-${resourceToken}'
var appServiceName = '${resourcePrefix}-app-${resourceToken}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-logs-${resourceToken}'
var applicationInsightsName = '${resourcePrefix}-ai-${resourceToken}'
var managedIdentityName = '${resourcePrefix}-identity-${resourceToken}'
var keyVaultName = '${resourcePrefix}-kv-${resourceToken}'
var postgresServerName = '${resourcePrefix}-postgres-${resourceToken}'
var postgresDatabaseName = '${resourcePrefix}_db_${resourceToken}'

// Generate secure password for PostgreSQL Server
var postgresAdminPassword = '${toUpper(uniqueString(subscription().id, resourceGroupName))}-${toLower(uniqueString(subscription().id, environmentName))}-Pg1!'

// Tags for resource management
var commonTags = {
  project: 'lamp-web-app'
  environment: environmentName
  managedBy: 'bicep'
}

// Resource Group Definition
// =============================================================================
// This resource group will contain all the resources for the lamp web app
// =============================================================================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}


// =============================================================================
// Monitoring Module Deployment
// =============================================================================
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  scope: resourceGroup
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    location: location
    tags: commonTags
    logRetentionInDays: 30
  }
}

// =============================================================================
// Managed Identity Module Deployment
// =============================================================================
module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managed-identity-deployment'
  scope: resourceGroup
  params: {
    managedIdentityName: managedIdentityName
    location: location
    tags: commonTags
  }
}

// =============================================================================
// Key Vault Module Deployment
// =============================================================================
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  scope: resourceGroup
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: commonTags
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
  }
}

// =============================================================================
// PostgreSQL Database Module Deployment
// =============================================================================
module postgresDatabase 'modules/postgresql.bicep' = {
  name: 'postgresql-deployment'
  scope: resourceGroup
  params: {
    postgresServerName: postgresServerName
    postgresDatabaseName: postgresDatabaseName
    location: location
    tags: commonTags
    administratorLogin: 'postgres'
    administratorLoginPassword: postgresAdminPassword
    keyVaultName: keyVault.outputs.keyVaultName
    environmentName: environmentName
  }
}

// =============================================================================
// Azure Container Registry Module Deployment (TEMPORARILY DISABLED FOR INITIAL DEPLOYMENT)
// =============================================================================
/*
module acr 'modules/acr.bicep' = {
  name: 'acr-deployment'
  scope: resourceGroup
  params: {
    containerRegistryName: containerRegistryName
    location: location
    containerRegistrySku: containerRegistrySku
    tags: commonTags
    sourceRepositoryUrl: sourceRepositoryUrl
    sourceBranch: sourceBranch
    imageName: imageName
    imageTag: imageTag
    dockerfilePath: dockerfilePath
    managedIdentityId: managedIdentity.outputs.managedIdentityId
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
  }
}
*/

// Simple ACR without build script for initial deployment
module simpleAcr 'modules/simple-acr.bicep' = {
  name: 'simple-acr-deployment'
  scope: resourceGroup
  params: {
    containerRegistryName: containerRegistryName
    location: location
    containerRegistrySku: containerRegistrySku
    tags: commonTags
  }
}

// =============================================================================
// App Service Module Deployment
// =============================================================================
module appService 'modules/appservice.bicep' = {
  name: 'appservice-deployment'
  scope: resourceGroup
  params: {
    appServicePlanName: appServicePlanName
    appServiceName: appServiceName
    location: location
    appServicePlanSku: appServicePlanSku
    tags: commonTags
    appPort: appPort
    containerRegistryLoginServer: simpleAcr.outputs.containerRegistryLoginServer
    applicationInsightsInstrumentationKey: monitoring.outputs.applicationInsightsInstrumentationKey
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    keyVaultUri: keyVault.outputs.keyVaultUri
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    managedIdentityId: managedIdentity.outputs.managedIdentityId
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
    managedIdentityClientId: managedIdentity.outputs.managedIdentityClientId
    postgresConnectionStringSecretName: postgresDatabase.outputs.connectionStringSecretName
  }
}

// =============================================================================
// ACR Integration Module (Role Assignment and Webhook)
// =============================================================================
module acrIntegration 'modules/acr-integration.bicep' = {
  name: 'acr-integration-deployment'
  scope: resourceGroup
  params: {
    containerRegistryId: acr.outputs.containerRegistryId
    containerRegistryName: acr.outputs.containerRegistryName
    appServicePrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
    webhookServiceUri: 'https://${appService.outputs.appServiceName}.scm.azurewebsites.net/api/registry/webhook'
    location: location
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the deployed App Service')
output appServiceName string = appService.outputs.appServiceName

@description('The default hostname of the deployed App Service')
output appServiceHostName string = appService.outputs.appServiceHostName

@description('The URL of the deployed application')
output appServiceUrl string = appService.outputs.appServiceUrl

@description('The name of the Container Registry')
output containerRegistryName string = acr.outputs.containerRegistryName

@description('The login server of the Container Registry')
output containerRegistryLoginServer string = acr.outputs.containerRegistryLoginServer

@description('The built image name')
output imageName string = acr.outputs.imageName

@description('The built image tag')
output imageTag string = acr.outputs.imageTag

@description('The full image name with registry URL')
output fullImageName string = acr.outputs.fullImageName

@description('The deployment script name used for building the image')
output buildScriptName string = acr.outputs.buildScriptName

@description('The resource ID of the App Service')
output appServiceId string = appService.outputs.appServiceId

@description('The principal ID of the App Service managed identity')
output appServicePrincipalId string = appService.outputs.appServicePrincipalId

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = monitoring.outputs.logAnalyticsWorkspaceName

@description('The name of the Application Insights instance')
output applicationInsightsName string = monitoring.outputs.applicationInsightsName

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = monitoring.outputs.applicationInsightsInstrumentationKey

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = monitoring.outputs.applicationInsightsConnectionString

@description('The name of the Key Vault')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('The name of the PostgreSQL Server')
output postgresServerName string = postgresDatabase.outputs.serverName

@description('The fully qualified domain name of the PostgreSQL Server')
output postgresServerFqdn string = postgresDatabase.outputs.serverFqdn

@description('The name of the PostgreSQL Database')
output postgresDatabaseName string = postgresDatabase.outputs.databaseName

@description('The connection string secret name in Key Vault')
output postgresConnectionStringSecretName string = postgresDatabase.outputs.connectionStringSecretName
