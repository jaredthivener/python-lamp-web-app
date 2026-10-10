// =============================================================================
// Monitoring Module (managed Prometheus + Container Insights logs)
// =============================================================================
// Microsoft's recommended pairing for AKS:
// - Metrics: an Azure Monitor workspace holds the cluster's Prometheus metrics.
//   Browse them in the portal: the cluster's Monitor > Dashboards with Grafana.
// - Logs: a Log Analytics workspace holds container logs, Kubernetes events and the
//   pod inventory (the "Logs and events" profile). Query them with KQL from the
//   cluster's Monitor > Logs.
// Each has a collection rule telling the cluster's agents what to send where.
// =============================================================================

@description('The name of the Azure Monitor workspace')
param monitorWorkspaceName string

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('The name of the Application Insights resource that receives the app\'s OpenTelemetry')
param applicationInsightsName string

@description('Most log data, in GB, the workspace accepts in a day. Collection pauses until the next day once it is reached.')
param dailyLogCapGb string = '0.2'

@description('The Azure region where resources will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Object ID of a user or group allowed to query the metrics. Empty grants nobody.')
param metricsReaderObjectId string = ''

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
}

resource prometheusEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {}
}

resource prometheusRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataCollectionEndpointId: prometheusEndpoint.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: ['Microsoft-PrometheusMetrics']
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'MonitoringAccount'
          accountResourceId: monitorWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-PrometheusMetrics']
        destinations: ['MonitoringAccount']
      }
    ]
  }
}

// =============================================================================
// Logs
// =============================================================================
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    // A ceiling on the bill: 0.2 GB a day is about 6 GB a month, of which the first
    // 5 GB are free.
    workspaceCapping: {
      dailyQuotaGb: json(dailyLogCapGb)
    }
  }
}

// The "Logs and events" profile, which Microsoft recommends alongside managed
// Prometheus: metrics come from Prometheus, so only the logs are collected here.
var logStreams = [
  'Microsoft-ContainerLogV2'
  'Microsoft-KubeEvents'
  'Microsoft-KubePodInventory'
]

resource containerInsightsRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: logStreams
          extensionSettings: {
            dataCollectionSettings: {
              interval: '1m'
              namespaceFilteringMode: 'Off'
              enableContainerLogV2: true
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: logStreams
        destinations: ['workspace']
      }
    ]
  }
}

// =============================================================================
// Application telemetry: what the app itself sends over OpenTelemetry (OTLP)
// =============================================================================
// Application Insights with OTLP support and managed workspaces: Azure creates the
// workspace that stores the metrics, and the rule that routes them, in a resource group
// of its own (as the portal's "Use managed workspaces: Yes" does). The cluster's agents
// accept the app's OTLP and forward it here. Microsoft documents this only in the
// portal; the properties are from the 2025-01-23-preview API specification.
// Metrics land in a Prometheus store, so Grafana queries them with PromQL.
resource applicationInsights 'Microsoft.Insights/components@2025-01-23-preview' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    AzureMonitorWorkspaceIngestionMode: 'Enabled'
  }
}

// The Grafana dashboard for the app's HTTP metrics, saved as an Azure resource. The tag is
// what lists it under the Application Insights resource's "Dashboards with Grafana".
// https://learn.microsoft.com/azure/azure-monitor/app/grafana-dashboards
// The same JSON imports into any Grafana: pick the Prometheus data source in its first dropdown.
resource lampDashboard 'Microsoft.Dashboard/dashboards@2025-09-01-preview' = {
  name: 'lamp-api'
  location: location
  tags: union(tags, { GrafanaDashboardResourceType: 'microsoft.insights/components' })
  properties: {}
}

resource lampDashboardDefinition 'Microsoft.Dashboard/dashboards/dashboardDefinitions@2025-09-01-preview' = {
  parent: lampDashboard
  name: 'default'
  properties: {
    serializedData: string(loadJsonContent('../../dashboards/lamp-api.json'))
  }
}

// Owning the subscription is not enough to read metric data: that takes this role
resource metricsReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(metricsReaderObjectId)) {
  name: guid(monitorWorkspace.id, metricsReaderObjectId, 'Monitoring Data Reader')
  scope: monitorWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b0d8363b-8ddd-447d-831f-62ca05bff136') // Monitoring Data Reader
    principalId: metricsReaderObjectId
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Azure Monitor workspace')
output monitorWorkspaceName string = monitorWorkspace.name

@description('The resource ID of the Prometheus data collection rule')
output prometheusRuleId string = prometheusRule.id

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the Container Insights data collection rule')
output containerInsightsRuleId string = containerInsightsRule.id

@description('The name of the Application Insights resource')
output applicationInsightsName string = applicationInsights.name

@description('The rule Azure created to route the app\'s OpenTelemetry. The cluster has to be associated with it, or its agent never starts listening for OTLP.')
output applicationInsightsRuleId string = applicationInsights.properties.DataCollectionRuleResourceId

@description('The resource ID of the Application Insights resource')
output applicationInsightsId string = applicationInsights.id

@description('Where the app\'s OpenTelemetry is sent. Not a secret on its own, but it identifies the resource.')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
