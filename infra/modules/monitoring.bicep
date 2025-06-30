// =============================================================================
// Monitoring Module (Log Analytics + Application Insights)
// =============================================================================
// This module creates monitoring resources for the application
// =============================================================================

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('The name of the Application Insights instance')
param applicationInsightsName string

@description('The Azure region where resources will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Log retention in days')
param logRetentionInDays int = 30

// =============================================================================
// Log Analytics Workspace for monitoring
// =============================================================================
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// =============================================================================
// Application Insights for application monitoring
// =============================================================================
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Application Insights instance')
output applicationInsightsName string = applicationInsights.name

@description('The resource ID of the Application Insights instance')
output applicationInsightsId string = applicationInsights.id

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
