// =============================================================================
// Azure Managed Grafana
// =============================================================================
// The one place to look at the app and the cluster: its managed identity reads the Azure Monitor
// workspace (metrics, PromQL) and the Log Analytics workspace (container logs and the app's spans,
// KQL). The dashboards are not Azure resources: .github/workflows/dashboard-deploy.yml imports
// infra/dashboards/*.json with `az grafana dashboard create`.
// Standard is the only tier a new instance can have: Microsoft deprecated Essential.
// https://learn.microsoft.com/azure/managed-grafana/overview#service-tiers
// Not on Azure Verified Modules: avm/res/dashboard/grafana is "Proposed" and has no version yet.
// =============================================================================

@description('The name of the Grafana instance: 2 to 23 characters (Azure enforces 23 although the template schema says 30), letters, digits and hyphens')
param name string

@description('The Azure region where the instance is created')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Resource ID of the Azure Monitor workspace that holds the Prometheus metrics')
param monitorWorkspaceId string

@description('Name of that workspace')
param monitorWorkspaceName string

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('Object ID of the user or group that administers Grafana. Empty grants nobody.')
param adminObjectId string = ''

resource monitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' existing = {
  name: monitorWorkspaceName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource grafana 'Microsoft.Dashboard/grafana@2025-08-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    size: 'X1'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Zone redundancy bills a second node ($0.05/hour here); the environment is for practice
    zoneRedundancy: 'Disabled'
    apiKey: 'Disabled' // service accounts are the way to automate; legacy API keys are deprecated
    deterministicOutboundIP: 'Disabled'
    publicNetworkAccess: 'Enabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: monitorWorkspaceId
        }
      ]
    }
  }
}

// Grafana's own identity reads the two workspaces, and nothing wider
resource metricsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(monitorWorkspace.id, grafana.id, 'Monitoring Data Reader')
  scope: monitorWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b0d8363b-8ddd-447d-831f-62ca05bff136') // Monitoring Data Reader
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, grafana.id, 'Log Analytics Reader')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893') // Log Analytics Reader
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Owning the subscription is not enough to open Grafana: it takes a Grafana role
resource admin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(adminObjectId)) {
  name: guid(grafana.id, adminObjectId, 'Grafana Admin')
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41') // Grafana Admin
    principalId: adminObjectId
  }
}

@description('The name of the Grafana instance')
output name string = grafana.name

@description('The address of Grafana')
output endpoint string = grafana.properties.endpoint
