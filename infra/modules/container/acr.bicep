// =============================================================================
// Azure Container Registry Module
// =============================================================================
// Holds the two things CI publishes: the app image, and the bundle of Kubernetes
// manifests that Flux applies. Nothing signs in with a password: CI pushes with its
// federated identity, and the cluster pulls with managed identities (see aks.bicep).
// =============================================================================

@description('The name of the Azure Container Registry')
param containerRegistryName string

@description('The Azure region where the registry will be deployed')
param location string

@description('Tags to apply to the registry')
param tags object = {}

// ponytail: nothing prunes old tags. Basic includes 10 GB and each push adds a few MB of
// new layers; add a scheduled `acr purge` when the registry's usage says it is needed.
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Container Registry')
output containerRegistryName string = containerRegistry.name

@description('The login server of the Container Registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
