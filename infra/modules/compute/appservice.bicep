// =============================================================================
// App Service Module (App Service Plan + App Service)
// =============================================================================
// This module creates an App Service Plan and App Service with container support
// =============================================================================

@description('The name of the App Service Plan')
param appServicePlanName string

@description('The name of the App Service')
param appServiceName string

@description('The Azure region where resources will be deployed')
param location string

@description('The SKU for the App Service Plan')
@allowed(['F1', 'D1', 'B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2', 'P1v3', 'P2v3', 'P3v3'])
param appServicePlanSku string = 'F1'

@description('Tags to apply to the resources')
param tags object = {}

@description('The port number the application listens on')
param appPort string = '8000'

@description('The login server of the Container Registry')
param containerRegistryLoginServer string

@description('Application Insights instrumentation key')
param applicationInsightsInstrumentationKey string

@description('Application Insights connection string')
@secure()
param applicationInsightsConnectionString string

@description('Key Vault URI for secret references')
param keyVaultUri string

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('The resource ID of the user-assigned managed identity')
param managedIdentityId string

@description('The principal ID of the user-assigned managed identity')
param managedIdentityPrincipalId string

@description('The client ID of the user-assigned managed identity')
param managedIdentityClientId string

@description('The PostgreSQL connection string secret name in Key Vault')
param postgresConnectionStringSecretName string

// =============================================================================
// App Service Plan (Linux)
// =============================================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux plans
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
}

// =============================================================================
// App Service (Web App) with Container Support
// =============================================================================
resource appService 'Microsoft.Web/sites@2024-11-01' = {
  name: appServiceName
  location: location
  tags: union(tags, {
    'azd-service-name': 'api'
  })
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    enabled: true
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    clientAffinityEnabled: false
    scmSiteAlsoStopped: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${containerRegistryLoginServer}/lamp-app:latest'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: managedIdentityClientId
      keyVaultReferenceIdentity: managedIdentityId
      alwaysOn: appServicePlanSku != 'F1' && appServicePlanSku != 'D1' ? true : false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: '/health'
      appSettings: [
        {
          name: 'PORT'
          value: appPort
        }
        {
          name: 'PYTHONPATH'
          value: '/app/src'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'WEBSITES_PORT'
          value: appPort
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsightsInstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: !empty(keyVaultUri)
            ? '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/ApplicationInsights--ConnectionString/)'
            : applicationInsightsConnectionString
        }
        {
          name: 'AZURE_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'ENVIRONMENT'
          value: tags.environment
        }
        {
          name: 'WEBSITE_HEALTHCHECK_MAXPINGFAILURES'
          value: '5'
        }
        {
          name: 'DOCKER_ENABLE_CI'
          value: 'true'
        }
        {
          name: 'WEBSITE_WEBDEPLOY_USE_SCM'
          value: 'true'
        }
        {
          name: 'KEY_VAULT_URI'
          value: keyVaultUri
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: managedIdentityClientId
        }
        {
          name: 'AzureKeyVaultReferenceCredentialClientId'
          value: managedIdentityClientId
        }
        {
          name: 'POSTGRES_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/${postgresConnectionStringSecretName}/)'
        }
      ]
      cors: {
        allowedOrigins: []
        supportCredentials: false
      }
      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
    }
  }
}

// =============================================================================
// App Service Basic Publishing Credentials Configuration
// =============================================================================
resource appServiceBasicPublishingCredentialsPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
  parent: appService
  name: 'scm'
  properties: {
    allow: true
  }
}

// =============================================================================
// Diagnostic Settings for App Service
// =============================================================================
resource appServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: appService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the App Service Plan')
output appServicePlanName string = appServicePlan.name

@description('The resource ID of the App Service Plan')
output appServicePlanId string = appServicePlan.id

@description('The name of the App Service')
output appServiceName string = appService.name

@description('The resource ID of the App Service')
output appServiceId string = appService.id

@description('The default hostname of the App Service')
output appServiceHostName string = appService.properties.defaultHostName

@description('The URL of the deployed application')
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'

@description('The principal ID of the App Service managed identity')
output appServicePrincipalId string = managedIdentityPrincipalId

@description('The App Service resource object')
output appService object = appService

@description('The webhook URL for continuous deployment')
output webhookUrl string = 'https://${appService.name}.scm.azurewebsites.net/api/registry/webhook'
