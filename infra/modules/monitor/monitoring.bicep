// =============================================================================
// Monitoring Module (managed Prometheus, Container Insights logs, the app's OpenTelemetry)
// =============================================================================
// Microsoft's recommended pairing for AKS:
// - Metrics: an Azure Monitor workspace holds the cluster's Prometheus metrics and the
//   app's OpenTelemetry metrics, all queried with PromQL (in Grafana: grafana.bicep).
// - Logs: a Log Analytics workspace holds container logs, Kubernetes events and the
//   pod inventory (the "Logs and events" profile), and the app's OpenTelemetry spans
//   (OTelSpans). Query them with KQL.
// Each has a collection rule telling the cluster's agents what to send where. The app's
// OpenTelemetry arrives through a third one, which the collector in k8s/observability
// writes to directly.
// =============================================================================

@description('The name of the Azure Monitor workspace')
param monitorWorkspaceName string

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('Most log data, in GB, the workspace accepts in a day. Collection pauses until the next day once it is reached.')
param dailyLogCapGb string = '0.2'

@description('The Azure region where resources will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Object ID of a user or group allowed to query the metrics. Empty grants nobody.')
param metricsReaderObjectId string = ''

@description('Object ID of the identity the OpenTelemetry collector signs in to Azure Monitor with')
param otlpPublisherObjectId string

resource monitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
}

resource prometheusEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {}
}

resource prometheusRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
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
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
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

resource containerInsightsRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
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
// The collector in k8s/observability posts OTLP/HTTP to this endpoint and rule, signed in with
// its workload identity: metrics go to the Azure Monitor workspace above, spans and logs to the
// Log Analytics workspace. Microsoft documents it as "Option 2: manual resource orchestration":
// https://learn.microsoft.com/azure/azure-monitor/containers/opentelemetry-protocol-ingestion
// Its sample rule also names an Application Insights resource, which is only there for that
// resource's own views; nothing here uses them, so the references are left out (tried on
// 2026-10-25: Azure accepts the rule, and spans, resources and metrics arrive).
resource otlpEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' = {
  name: '${monitorWorkspaceName}-otlp'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource otlpRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: '${monitorWorkspaceName}-otlp'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: otlpEndpoint.id
    directDataSources: {
      otelMetrics: [
        {
          name: 'otelMetrics'
          streams: ['Custom-Metrics-Otel']
          enrichWithResourceAttributes: ['*']
        }
      ]
      otelLogs: [
        {
          name: 'otelLogs'
          streams: ['Microsoft-OTel-Logs']
          enrichWithResourceAttributes: ['*']
        }
      ]
      otelTraces: [
        {
          name: 'otelTraces'
          streams: [
            'Microsoft-OTel-Traces-Spans'
            'Microsoft-OTel-Traces-Events'
            'Microsoft-OTel-Traces-Resources'
          ]
          enrichWithResourceAttributes: ['*']
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'metrics'
          accountResourceId: monitorWorkspace.id
        }
      ]
      logAnalytics: [
        {
          name: 'logs'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Custom-Metrics-Otel']
        destinations: ['metrics']
      }
      {
        streams: [
          'Microsoft-OTel-Logs'
          'Microsoft-OTel-Traces-Spans'
          'Microsoft-OTel-Traces-Events'
          'Microsoft-OTel-Traces-Resources'
        ]
        destinations: ['logs']
      }
    ]
  }
}

// What lets the collector write to the rule, and to nothing else
resource otlpPublisherRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(otlpRule.id, otlpPublisherObjectId, 'Monitoring Metrics Publisher')
  scope: otlpRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalId: otlpPublisherObjectId
    principalType: 'ServicePrincipal'
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

@description('The resource ID of the Azure Monitor workspace')
output monitorWorkspaceId string = monitorWorkspace.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The immutable ID of the OTLP data collection rule, which goes in the collector\'s endpoint paths')
output otlpRuleImmutableId string = otlpRule.properties.immutableId

@description('The address the collector sends spans and logs to (the endpoint\'s log ingestion address)')
output otlpLogsEndpoint string = otlpEndpoint.properties.logsIngestion.endpoint

@description('The address the collector sends metrics to (the endpoint\'s metrics ingestion address)')
output otlpMetricsEndpoint string = otlpEndpoint.properties.metricsIngestion.endpoint
