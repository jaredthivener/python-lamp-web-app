targetScope = 'subscription'

// =============================================================================
// Azure Infrastructure for Lamp Web App - Main Template
// =============================================================================
// An AKS cluster that reconciles itself from this repository's k8s/ folder.
//
// Architecture:
// - Network module: virtual network, private DNS for Postgres, the site's public IP
// - Monitoring module: managed Prometheus for metrics, Container Insights for logs,
//   Application Insights for the app's own OpenTelemetry
// - ACR module: registry for the app image and the Flux manifest bundle
// - PostgreSQL module: private flexible server with Entra-only sign-in
// - AKS module: the cluster, its identities, and the Flux (GitOps) configuration
// - Schedule module: stops the cluster overnight and starts it in the morning
//
// Security Features:
// - No passwords or keys anywhere: every hop uses a managed identity
// - Kubernetes sign-in and authorization through Entra ID, local accounts disabled
// - Postgres reachable only from inside the virtual network
// =============================================================================
@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = 'rg-lamp-web-app'

@description('The name of the environment (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string

@description('The Azure region where resources will be deployed. Credit-based subscriptions cannot create PostgreSQL flexible servers in every region: `az postgres flexible-server list-skus -l <region>` shows whether one is open to yours.')
param location string = 'westus3'

@description('Kubernetes minor version. AKS applies new patch releases of it automatically.')
param kubernetesVersion string = '1.36'

@description('VM size for every node. Must be an Arm64 size with a local disk, which is what an ephemeral OS disk lives on.')
param nodeVmSize string = 'Standard_D2pds_v6'

@description('How many nodes the cluster runs. Each one costs about 9 cents for every hour the cluster is up. Two are not enough: see the node pool in modules/compute/aks.bicep.')
@minValue(3)
param nodeCount int = 3

@description('Object ID of the Entra user or group that administers the cluster with kubectl. Empty grants nobody.')
param clusterAdminObjectId string = ''

@description('When the cluster starts each day, as HH:mm in scheduleTimeZone')
param clusterStartTime string = '09:00'

@description('When the cluster stops each day, as HH:mm in scheduleTimeZone')
param clusterStopTime string = '17:00'

@description('Windows time zone name the schedule runs in')
param scheduleTimeZone string = 'Eastern Standard Time'

// Generate unique resource names using resource token
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var resourcePrefix = 'lamp'

// Tags for resource management
var commonTags = {
  project: 'lamp-web-app'
  environment: environmentName
  managedBy: 'bicep'
}

// Kubernetes names the identities are trusted for. k8s/ has to use the same ones.
var appNamespace = 'lamp'
var appServiceAccount = 'lamp-app'
var postgresDatabaseName = 'lamp'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

module network 'modules/network/network.bicep' = {
  name: 'network-deployment'
  scope: resourceGroup
  params: {
    virtualNetworkName: '${resourcePrefix}-vnet-${resourceToken}'
    publicIpName: '${resourcePrefix}-ip-${resourceToken}'
    dnsLabel: '${resourcePrefix}-${resourceToken}'
    location: location
    tags: commonTags
  }
}

module monitoring 'modules/monitor/monitoring.bicep' = {
  name: 'monitoring-deployment'
  scope: resourceGroup
  params: {
    monitorWorkspaceName: '${resourcePrefix}-metrics-${resourceToken}'
    logAnalyticsWorkspaceName: '${resourcePrefix}-logs-${resourceToken}'
    applicationInsightsName: '${resourcePrefix}-appinsights-${resourceToken}'
    location: location
    tags: commonTags
    metricsReaderObjectId: clusterAdminObjectId
  }
}

// Three identities, one job each. None of them has a secret to leak.
module clusterIdentity 'modules/security/managed-identity.bicep' = {
  name: 'cluster-identity-deployment'
  scope: resourceGroup
  params: {
    managedIdentityName: '${resourcePrefix}-aks-${resourceToken}' // the control plane: load balancer and network changes
    location: location
    tags: commonTags
  }
}

module appIdentity 'modules/security/managed-identity.bicep' = {
  name: 'app-identity-deployment'
  scope: resourceGroup
  params: {
    managedIdentityName: '${resourcePrefix}-app-${resourceToken}' // the lamp pods: signing in to Postgres
    location: location
    tags: commonTags
  }
}

module fluxIdentity 'modules/security/managed-identity.bicep' = {
  name: 'flux-identity-deployment'
  scope: resourceGroup
  params: {
    managedIdentityName: '${resourcePrefix}-flux-${resourceToken}' // Flux: pulling the manifest bundle
    location: location
    tags: commonTags
  }
}

module acr 'modules/container/acr.bicep' = {
  name: 'acr-deployment'
  scope: resourceGroup
  params: {
    containerRegistryName: '${resourcePrefix}acr${resourceToken}'
    location: location
    tags: commonTags
  }
}

module postgresDatabase 'modules/database/postgresql.bicep' = {
  name: 'postgresql-deployment'
  scope: resourceGroup
  params: {
    postgresServerName: '${resourcePrefix}-postgres-${resourceToken}'
    postgresDatabaseName: postgresDatabaseName
    location: location
    tags: commonTags
    delegatedSubnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresDnsZoneId
    administratorPrincipalId: appIdentity.outputs.managedIdentityPrincipalId
    administratorPrincipalName: appIdentity.outputs.managedIdentityName
  }
}

module aks 'modules/compute/aks.bicep' = {
  name: 'aks-deployment'
  scope: resourceGroup
  params: {
    clusterName: '${resourcePrefix}-aks-${resourceToken}'
    location: location
    tags: commonTags
    kubernetesVersion: kubernetesVersion
    nodeVmSize: nodeVmSize
    nodeCount: nodeCount
    clusterAdminObjectId: clusterAdminObjectId
    clusterIdentityName: clusterIdentity.outputs.managedIdentityName
    appIdentityName: appIdentity.outputs.managedIdentityName
    fluxIdentityName: fluxIdentity.outputs.managedIdentityName
    appNamespace: appNamespace
    appServiceAccount: appServiceAccount
    virtualNetworkName: network.outputs.virtualNetworkName
    nodeSubnetId: network.outputs.nodeSubnetId
    publicIpName: network.outputs.publicIpName
    containerRegistryName: acr.outputs.containerRegistryName
    prometheusRuleId: monitoring.outputs.prometheusRuleId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    containerInsightsRuleId: monitoring.outputs.containerInsightsRuleId
    applicationInsightsRuleId: monitoring.outputs.applicationInsightsRuleId
    // Everything the manifests in k8s/ need to know about this deployment
    manifestValues: {
      LAMP_HOST: network.outputs.hostName
      PUBLIC_IP_NAME: network.outputs.publicIpName
      PUBLIC_IP_RESOURCE_GROUP: resourceGroupName
      APP_IDENTITY_CLIENT_ID: appIdentity.outputs.managedIdentityClientId
      APPLICATIONINSIGHTS_CONNECTION_STRING: monitoring.outputs.applicationInsightsConnectionString
      POSTGRES_CONNECTION_STRING: 'host=${postgresDatabase.outputs.serverFqdn} dbname=${postgresDatabaseName} user=${appIdentity.outputs.managedIdentityName} sslmode=require'
    }
  }
}

module schedule 'modules/compute/schedule.bicep' = {
  name: 'schedule-deployment'
  scope: resourceGroup
  params: {
    clusterName: aks.outputs.clusterName
    location: location
    tags: commonTags
    startTime: clusterStartTime
    stopTime: clusterStopTime
    timeZone: scheduleTimeZone
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('Where the lamp is served')
output lampUrl string = 'https://${network.outputs.hostName}'

@description('The name of the AKS cluster')
output clusterName string = aks.outputs.clusterName

@description('Fetches kubectl credentials for the cluster')
output getCredentialsCommand string = 'az aks get-credentials --resource-group ${resourceGroupName} --name ${aks.outputs.clusterName}'

@description('The name of the Container Registry')
output containerRegistryName string = acr.outputs.containerRegistryName

@description('The login server of the Container Registry')
output containerRegistryLoginServer string = acr.outputs.containerRegistryLoginServer

@description('The fully qualified domain name of the PostgreSQL Server')
output postgresServerFqdn string = postgresDatabase.outputs.serverFqdn

@description('The Azure Monitor workspace that stores the cluster\'s Prometheus metrics')
output monitorWorkspaceName string = monitoring.outputs.monitorWorkspaceName
