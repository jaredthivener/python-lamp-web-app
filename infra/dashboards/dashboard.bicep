// =============================================================================
// The Grafana dashboard for the app's HTTP metrics, saved as an Azure resource
// =============================================================================
// Deployed on its own, by .github/workflows/dashboard-deploy.yml, to the resource group the
// infrastructure created. It changes much more often than the cluster does, and Microsoft's
// guidance is one pipeline per layer, matched to how often its resources change:
// https://learn.microsoft.com/azure/well-architected/operational-excellence/infrastructure-as-code-design
//
// The tag is what lists it under the Application Insights resource's "Dashboards with Grafana".
// https://learn.microsoft.com/azure/azure-monitor/app/grafana-dashboards

@description('The Azure region of the resource group')
param location string = resourceGroup().location

@description('The name of the environment (e.g., dev, staging, prod)')
param environmentName string = 'dev'

var tags = {
  project: 'lamp-web-app'
  environment: environmentName
  managedBy: 'bicep'
}

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
    serializedData: string(loadJsonContent('lamp-api.json'))
  }
}
