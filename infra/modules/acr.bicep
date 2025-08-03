// =============================================================================
// Container Registry Module
// =============================================================================
// This module creates an Azure Container Registry with security best practices
// =============================================================================

@description('The name of the Container Registry')
param containerRegistryName string

@description('The Azure region where resources will be deployed')
param location string

@description('The SKU name for the Container Registry')
param containerRegistrySku string = 'Basic'

@description('Tags to apply to the container registry')
param tags object = {}

@description('The Git repository URL containing the source code and Dockerfile')
param sourceRepositoryUrl string

@description('The Git branch to use for building the image')
param sourceBranch string = 'main'

@description('The name of the Docker image to build')
param imageName string = 'lamp-app'

@description('The tag for the Docker image')
param imageTag string = 'latest'

@description('The path to the Dockerfile relative to the repository root')
param dockerfilePath string = 'Dockerfile'

// Note: Managed identity parameters removed since deployment script is disabled

// =============================================================================
// Azure Container Registry
// =============================================================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: false
    policies: {
      quarantinePolicy: {
        status: containerRegistrySku == 'Premium' ? 'enabled' : 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: containerRegistrySku == 'Premium' ? 'enabled' : 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: containerRegistrySku != 'Basic' ? 'enabled' : 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: containerRegistrySku == 'Premium' ? true : false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSet: containerRegistrySku == 'Basic' ? null : {
      defaultAction: 'Allow'
      ipRules: []
    }
    zoneRedundancy: containerRegistrySku == 'Premium' ? 'Enabled' : 'Disabled'
  }
}

// =============================================================================
// Role Assignment and Deployment Script (DISABLED)
// =============================================================================
// Note: These are handled in acr-integration module or built manually
// Role assignments for app service will be handled in acr-integration module
// Build script is disabled - use manual build command from outputs

/*
resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'AcrPush')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource buildScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'build-push-image-${uniqueString(containerRegistry.id, location)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.75.0'
    timeout: 'PT45M'
    retentionInterval: 'PT2H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'ACR_NAME'
        value: containerRegistry.name
      }
      {
        name: 'SOURCE_URL'
        value: sourceRepositoryUrl
      }
      {
        name: 'IMAGE_NAME'
        value: imageName
      }
      {
        name: 'IMAGE_TAG'
        value: imageTag
      }
      {
        name: 'DOCKERFILE_PATH' 
        value: dockerfilePath
      }
      {
        name: 'SOURCE_BRANCH'
        value: sourceBranch
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Starting Container Image Build Process"
      echo "Registry: $ACR_NAME"
      echo "Source: $SOURCE_URL"
      echo "Image: $IMAGE_NAME:$IMAGE_TAG"
      echo "Branch: $SOURCE_BRANCH"
      
      # Wait for ACR to be fully available
      echo "Waiting for ACR to be fully available..."
      for i in {1..30}; do
        if az acr show --name $ACR_NAME --query "provisioningState" -o tsv 2>/dev/null | grep -q "Succeeded"; then
          echo "ACR is available"
          break
        fi
        echo "Waiting for ACR... attempt $i/30"
        sleep 10
      done

      # Verify ACR access
      echo "Verifying ACR access..."
      az acr show --name $ACR_NAME --query "name" -o tsv

      # Build and push using ACR build directly from GitHub
      echo "Building and pushing image using ACR Tasks..."
      
      BUILD_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
      
      az acr build \
        --registry $ACR_NAME \
        --image "$IMAGE_NAME:$IMAGE_TAG" \
        --image "$IMAGE_NAME:$BUILD_TIMESTAMP" \
        --file $DOCKERFILE_PATH \
        --platform linux/amd64 \
        $SOURCE_URL#$SOURCE_BRANCH

      echo "Build completed successfully!"
      
      # Verify the image exists
      echo "Verifying image was pushed..."
      
      sleep 30  # Wait for image to be available
      
      if az acr repository show --name $ACR_NAME --image "$IMAGE_NAME:$IMAGE_TAG" >/dev/null 2>&1; then
        echo "Image $IMAGE_NAME:$IMAGE_TAG successfully available in registry"
        az acr repository show-tags --name $ACR_NAME --repository $IMAGE_NAME --output table
      else
        echo "Image verification failed"
        exit 1
      fi

      echo "Container Image Build Complete!"
      echo "Registry: $ACR_NAME.azurecr.io"
      echo "Image: $IMAGE_NAME:$IMAGE_TAG"
      echo "Build ID: $BUILD_TIMESTAMP"
    '''
  }
  dependsOn: [
    acrPushRoleAssignment
  ]
}
*/


// =============================================================================
// Outputs
// =============================================================================
@description('The name of the Container Registry')
output containerRegistryName string = containerRegistry.name

@description('The login server of the Container Registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The resource ID of the Container Registry')
output containerRegistryId string = containerRegistry.id

@description('The resource object of the Container Registry')
output containerRegistry object = containerRegistry

@description('The name of the built image')
output imageName string = imageName

@description('The tag of the built image') 
output imageTag string = imageTag

@description('The full image name with registry URL')
output fullImageName string = '${containerRegistry.properties.loginServer}/${imageName}:${imageTag}'

@description('The source repository URL for manual build')
output sourceRepositoryUrl string = sourceRepositoryUrl

@description('The source branch for manual build')
output sourceBranch string = sourceBranch

@description('The dockerfile path for manual build')
output dockerfilePath string = dockerfilePath

// @description('The deployment script name (commented out)')
// output buildScriptName string = buildScript.name
