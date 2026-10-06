// =============================================================================
// AKS Module
// =============================================================================
// The cluster and everything that has to be wired to it from the Azure side:
// - Arm64 (Cobalt) nodes on Azure Linux with ephemeral OS disks
// - Entra ID sign-in with Azure RBAC, local accounts disabled
// - Azure CNI Overlay with the Cilium dataplane and network policy
// - Workload identity, so pods reach Azure services without secrets
// - Managed Prometheus for metrics, Container Insights for logs
// - The Flux extension, pointed at the manifest bundle CI publishes
// =============================================================================

@description('The name of the AKS cluster')
param clusterName string

@description('The Azure region where the cluster will be deployed')
param location string

@description('Tags to apply to the resources')
param tags object = {}

@description('Kubernetes version, as major.minor to follow patch releases')
param kubernetesVersion string

@description('VM size for every node')
param nodeVmSize string

@description('How many nodes the cluster runs')
param nodeCount int

@description('Object ID of the Entra user or group that administers the cluster. Empty grants nobody.')
param clusterAdminObjectId string

@description('Name of the managed identity the control plane runs as')
param clusterIdentityName string

@description('Name of the managed identity the lamp pods run as')
param appIdentityName string

@description('Name of the managed identity Flux pulls the manifest bundle with')
param fluxIdentityName string

@description('Kubernetes namespace of the service account trusted to act as the app identity')
param appNamespace string

@description('Kubernetes service account trusted to act as the app identity')
param appServiceAccount string

@description('Name of the virtual network the nodes join')
param virtualNetworkName string

@description('Resource ID of the subnet for nodes')
param nodeSubnetId string

@description('Name of the public IP address the gateway serves the site on')
param publicIpName string

@description('Name of the container registry the cluster pulls from')
param containerRegistryName string

@description('Resource ID of the data collection rule for Prometheus metrics')
param prometheusRuleId string

@description('Resource ID of the Log Analytics workspace that receives container logs')
param logAnalyticsWorkspaceId string

@description('Resource ID of the data collection rule for container logs')
param containerInsightsRuleId string

@description('Values substituted for the placeholders, written like \${LAMP_HOST}, in the manifests under k8s/app')
param manifestValues object

var roles = {
  networkContributor: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  clusterAdmin: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b' // Azure Kubernetes Service RBAC Cluster Admin
}

resource clusterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: clusterIdentityName
}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: appIdentityName
}

resource fluxIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: fluxIdentityName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: virtualNetworkName
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' existing = {
  name: publicIpName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

// =============================================================================
// What the control plane may touch: the network its nodes join, and the site's address
// =============================================================================
resource networkRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(virtualNetwork.id, clusterIdentity.id, roles.networkContributor)
  scope: virtualNetwork
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.networkContributor)
    principalId: clusterIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource publicIpRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(publicIp.id, clusterIdentity.id, roles.networkContributor)
  scope: publicIp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.networkContributor)
    principalId: clusterIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// AKS Cluster
// =============================================================================
resource aks 'Microsoft.ContainerService/managedClusters@2026-05-01' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Free' // no uptime SLA: right for a cluster that is switched off every night
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${clusterIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    nodeResourceGroup: '${resourceGroup().name}-nodes'

    // Who gets in: Entra ID identities holding an Azure role. There is no shared admin
    // kubeconfig to leak, and access is granted and revoked like any other Azure access.
    disableLocalAccounts: true
    enableRBAC: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: tenant().tenantId
    }

    // One pool, a fixed number of nodes. Microsoft's guidance is a dedicated (tainted)
    // system pool of at least two nodes, a separate user pool and the cluster autoscaler.
    // That is at least four nodes, and the budget covers three. Tried with fewer:
    // a fenced-off system node sat half empty, and the autoscaler kept adding a node and
    // taking it away again as pods shuffled between nearly full ones. A fixed count also
    // makes the bill predictable, which matters under a spending limit.
    //
    // Why three and not two: after a start, AKS's own components fill the first node
    // that is ready to 99%. The app needs its two replicas on different nodes, so it
    // needs two nodes that still have room.
    // To practise autoscaling, add a pool of its own: az aks nodepool add --enable-cluster-autoscaler
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        // The OS lives on the VM's own local disk: free, faster than a managed disk,
        // and a node that is reimaged or replaced starts clean.
        osDiskType: 'Ephemeral'
        osDiskSizeGB: 100 // the local disk on the default size is 110 GiB, and what the OS disk leaves is unusable
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: nodeSubnetId
        availabilityZones: ['1', '2', '3'] // the scale set places its nodes in different zones
        upgradeSettings: {
          maxSurge: '1' // upgrades add a node before they take one away
        }
      }
    ]

    networkProfile: {
      // Nodes take addresses from the subnet and pods from an overlay range, so the
      // subnet never runs out. Cilium (eBPF) routes traffic and enforces NetworkPolicy.
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer' // a NAT gateway is the usual advice, at about $32 a month
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
      }
    }

    // Kubernetes patch releases and node images arrive by themselves, inside the
    // maintenance windows below.
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }

    oidcIssuerProfile: {
      enabled: true
    }
    // No image cleaner: stopping the cluster discards its nodes, so every morning starts
    // with empty disks, and the cleaner's scan job reserves a quarter of a node while it runs.
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // No workload here mounts Azure Files or Blob storage. The disk driver stays for
    // the day one needs a PersistentVolume.
    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: false
      }
      blobCSIDriver: {
        enabled: false
      }
      snapshotController: {
        enabled: false
      }
    }

    azureMonitorProfile: {
      metrics: {
        enabled: true
      }
    }

    // Container Insights: the agent that ships container logs and Kubernetes events
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
  }
  dependsOn: [
    networkRoleAssignment
    publicIpRoleAssignment
  ]
}

// Upgrades need the cluster running, so the windows sit inside its daytime schedule.
// Sunday 10:00-14:00 US Eastern; move them if you move clusterStartTime/clusterStopTime.
resource maintenanceWindows 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2026-05-01' = [
  for name in ['aksManagedAutoUpgradeSchedule', 'aksManagedNodeOSUpgradeSchedule']: {
    parent: aks
    name: name
    properties: {
      maintenanceWindow: {
        schedule: {
          weekly: {
            intervalWeeks: 1
            dayOfWeek: 'Sunday'
          }
        }
        durationHours: 4
        utcOffset: '-05:00'
        startTime: '10:00'
      }
    }
  }
]

// =============================================================================
// Access
// =============================================================================
resource clusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(clusterAdminObjectId)) {
  name: guid(aks.id, clusterAdminObjectId, roles.clusterAdmin)
  scope: aks
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.clusterAdmin)
    principalId: clusterAdminObjectId
  }
}

// Nodes pull the app image as the kubelet's identity
resource kubeletPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, aks.id, 'kubelet', roles.acrPull)
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource fluxPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, fluxIdentity.id, roles.acrPull)
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
    principalId: fluxIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Workload identity: a token Kubernetes issues to one service account is accepted by
// Entra ID as proof of being this managed identity. No secret is stored anywhere.
resource appFederation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  parent: appIdentity
  name: clusterName
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${appNamespace}:${appServiceAccount}'
    audiences: ['api://AzureADTokenExchange']
  }
}

resource fluxFederation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  parent: fluxIdentity
  name: clusterName
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:flux-system:source-controller'
    audiences: ['api://AzureADTokenExchange']
  }
}

// =============================================================================
// Monitoring: tells the cluster's agents where to send metrics and logs
// =============================================================================
resource prometheusAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsMetricsExtension'
  scope: aks
  properties: {
    dataCollectionRuleId: prometheusRuleId
  }
}

resource containerInsightsAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'ContainerInsightsExtension'
  scope: aks
  properties: {
    dataCollectionRuleId: containerInsightsRuleId
  }
}

// =============================================================================
// GitOps: Flux keeps the cluster matching the manifest bundle CI publishes
// =============================================================================
resource flux 'Microsoft.KubernetesConfiguration/extensions@2025-03-01' = {
  name: 'flux'
  scope: aks
  properties: {
    extensionType: 'microsoft.flux'
    autoUpgradeMinorVersion: true
    scope: {
      cluster: {
        releaseNamespace: 'flux-system'
      }
    }
    configurationSettings: {
      'workloadIdentity.enable': 'true'
      'workloadIdentity.azureClientId': fluxIdentity.properties.clientId
      'workloadIdentity.azureTenantId': tenant().tenantId
    }
  }
}

// The bundle is k8s/ from this repository, pushed to the registry as an OCI artifact
// with the app image's tag written in (see the publish job in .github/workflows/ci.yml).
// Until CI has pushed one, Flux reports the source as not found and keeps trying.
resource fluxConfiguration 'Microsoft.KubernetesConfiguration/fluxConfigurations@2025-04-01' = {
  name: 'lamp'
  scope: aks
  properties: {
    scope: 'cluster'
    namespace: 'flux-system'
    sourceKind: 'OCIRepository'
    ociRepository: {
      url: 'oci://${containerRegistry.properties.loginServer}/manifests/lamp'
      repositoryRef: {
        tag: 'latest'
      }
      syncIntervalInSeconds: 60
      useWorkloadIdentity: true
    }
    kustomizations: {
      // Cluster add-ons (cert-manager) first: the app's manifests use their CRDs
      infrastructure: {
        path: './infrastructure'
        prune: true
        wait: true
        timeoutInSeconds: 600
      }
      app: {
        path: './app'
        dependsOn: ['infrastructure']
        prune: true
        wait: true
        timeoutInSeconds: 600
        postBuild: {
          substitute: manifestValues
        }
      }
    }
  }
  dependsOn: [
    flux
    fluxFederation
    fluxPullRoleAssignment
  ]
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the AKS cluster')
output clusterName string = aks.name
