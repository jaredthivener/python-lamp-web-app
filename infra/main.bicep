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
module clusterIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'cluster-identity-deployment'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}-aks-${resourceToken}' // the control plane: load balancer and network changes
    location: location
    tags: commonTags
  }
}

module appIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'app-identity-deployment'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}-app-${resourceToken}' // the lamp pods: signing in to Postgres
    location: location
    tags: commonTags
  }
}

module fluxIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'flux-identity-deployment'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}-flux-${resourceToken}' // Flux: pulling the manifest bundle
    location: location
    tags: commonTags
  }
}

module acr 'br/public:avm/res/container-registry/registry:0.13.1' = {
  name: 'acr-deployment'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}acr${resourceToken}'
    location: location
    tags: commonTags
    // The module's defaults are Premium and zone redundancy. Basic is the cheapest tier, and enough
    // for one image and one manifest bundle: no private link, geo-replication or zone redundancy.
    acrSku: 'Basic'
    zoneRedundancy: 'Disabled'
    acrAdminUserEnabled: false
    // What the registry has today. The module leaves it unset, and the AcrPull assignments for the nodes and
    // for Flux (modules/compute/aks.bicep) only work in this mode, not in the newer attribute-based one.
    roleAssignmentMode: 'LegacyRegistryPermissions'
    // Microsoft recommends refusing broad ARM tokens (this set to 'disabled'). The module's default is
    // that; it is kept as it was here until `az acr login` in CI has been tried against it.
    azureADAuthenticationAsArmPolicyStatus: 'enabled'
  }
}

module postgresDatabase 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.16.1' = {
  name: 'postgresql-deployment'
  scope: resourceGroup
  params: {
    name: '${resourcePrefix}-postgres-${resourceToken}'
    location: location
    tags: commonTags
    // The module's defaults are zone-redundant high availability, geo-redundant backups and Defender's
    // threat protection. This is a practice environment on a credit subscription, so the cheapest
    // server is written out instead: one burstable core, no standby, no geo copy, no Defender.
    skuName: 'Standard_B1ms'
    tier: 'Burstable'
    availabilityZone: -1 // no preference: Azure picks, as it did before
    highAvailability: 'Disabled'
    geoRedundantBackup: 'Disabled'
    backupRetentionDays: 7
    storageSizeGB: 32
    version: '18'
    serverThreatProtection: 'Disabled'
    enableAdvancedThreatProtection: false
    // Azure picks the maintenance window, as it did before (the module's default is Sunday 01:00)
    maintenanceWindow: {
      customWindow: 'Disabled'
    }
    // Private only: the server lives in the delegated subnet and is reached through its private DNS zone
    delegatedSubnetResourceId: network.outputs.postgresSubnetId
    privateDnsZoneArmResourceId: network.outputs.postgresDnsZoneId
    publicNetworkAccess: 'Disabled'
    // No password: the app's identity is the server's Entra administrator, and signs in with a token
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: tenant().tenantId
    }
    administrators: [
      {
        objectId: appIdentity.outputs.principalId
        principalName: appIdentity.outputs.name
        principalType: 'ServicePrincipal'
      }
    ]
    databases: [
      {
        name: postgresDatabaseName
        charset: 'UTF8'
        collation: 'en_US.utf8'
      }
    ]
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
    clusterIdentityName: clusterIdentity.outputs.name
    appIdentityName: appIdentity.outputs.name
    fluxIdentityName: fluxIdentity.outputs.name
    appNamespace: appNamespace
    appServiceAccount: appServiceAccount
    virtualNetworkName: network.outputs.virtualNetworkName
    nodeSubnetId: network.outputs.nodeSubnetId
    publicIpName: network.outputs.publicIpName
    containerRegistryName: acr.outputs.name
    prometheusRuleId: monitoring.outputs.prometheusRuleId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    containerInsightsRuleId: monitoring.outputs.containerInsightsRuleId
    applicationInsightsRuleId: monitoring.outputs.applicationInsightsRuleId
    // Everything the manifests in k8s/ need to know about this deployment
    manifestValues: {
      LAMP_HOST: network.outputs.hostName
      PUBLIC_IP_NAME: network.outputs.publicIpName
      PUBLIC_IP_RESOURCE_GROUP: resourceGroupName
      APP_IDENTITY_CLIENT_ID: appIdentity.outputs.clientId
      APPLICATIONINSIGHTS_CONNECTION_STRING: monitoring.outputs.applicationInsightsConnectionString
      POSTGRES_CONNECTION_STRING: 'host=${postgresDatabase.outputs.fqdn!} dbname=${postgresDatabaseName} user=${appIdentity.outputs.name} sslmode=require'
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
output containerRegistryName string = acr.outputs.name

@description('The login server of the Container Registry')
output containerRegistryLoginServer string = acr.outputs.loginServer

@description('The fully qualified domain name of the PostgreSQL Server')
output postgresServerFqdn string = postgresDatabase.outputs.fqdn!

@description('The Azure Monitor workspace that stores the cluster\'s Prometheus metrics')
output monitorWorkspaceName string = monitoring.outputs.monitorWorkspaceName
