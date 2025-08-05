// =============================================================================
// Container Registry Module (Combined)
// =============================================================================
// This module creates an Azure Container Registry with security best practices,
// role assignments, and webhook integration for continuous deployment
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

@description('The resource ID of the user-assigned managed identity for deployment scripts')
param managedIdentityId string

@description('The principal ID of the user-assigned managed identity for deployment scripts')
param managedIdentityPrincipalId string

@description('The principal ID of the App Service managed identity for ACR access')
param appServicePrincipalId string

@description('The service URI for the webhook (optional - can be empty string to skip webhook)')
@secure()
param webhookServiceUri string

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
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// =============================================================================
// Role Assignments for Container Registry Access
// =============================================================================

// Grant the managed identity AcrPush role for building images
resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'AcrPush')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8311e382-0749-4cb8-b61a-304f252e45ec'
    ) // AcrPush role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the managed identity Contributor role on the registry for full management
resource acrContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'Contributor')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    ) // Contributor role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the managed identity Reader role on the resource group for listing resources
resource resourceGroupReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentityPrincipalId, 'Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    ) // Reader role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Grant App Service managed identity AcrPull access for pulling images
resource appServiceAcrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, appServicePrincipalId, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    ) // AcrPull role
    principalId: appServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Container Registry Webhook for Continuous Deployment (Optional)
// =============================================================================
resource containerRegistryWebhook 'Microsoft.ContainerRegistry/registries/webhooks@2023-07-01' = if (!empty(webhookServiceUri)) {
  name: 'lampappwebhook'
  parent: containerRegistry
  location: location
  properties: {
    serviceUri: webhookServiceUri
    actions: ['push']
    scope: '${imageName}:*'
    status: 'enabled'
    customHeaders: {
      'Content-Type': 'application/json'
    }
  }
  dependsOn: [
    appServiceAcrPullRoleAssignment
  ]
}

// =============================================================================
// Deployment Script for Building Container Image
// =============================================================================
resource buildScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${containerRegistryName}-build-script'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.76.0'
    timeout: 'PT15M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'ACR_NAME'
        value: containerRegistryName
      }
      {
        name: 'SOURCE_LOCATION'
        value: sourceRepositoryUrl
      }
      {
        name: 'BRANCH'
        value: sourceBranch
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
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "=== Starting Container Image Build ==="
      echo "Registry: $ACR_NAME"
      echo "Source: $SOURCE_LOCATION"
      echo "Branch: $BRANCH"
      echo "Image: $IMAGE_NAME:$IMAGE_TAG"
      echo "Dockerfile: $DOCKERFILE_PATH"
      echo "================================================"

      # Get the login server
      LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)
      echo "Login server: $LOGIN_SERVER"

      # Note: We don't need to login to ACR for 'az acr build' as it uses managed identity automatically
      echo "Using managed identity for ACR authentication..."

      # Check if image already exists
      if az acr repository show --name "$ACR_NAME" --image "$IMAGE_NAME:$IMAGE_TAG" >/dev/null 2>&1; then
        echo "⚠️  Image $IMAGE_NAME:$IMAGE_TAG already exists in registry"
        echo "Checking if rebuild is needed..."

        # Get existing image creation time
        EXISTING_CREATED=$(az acr repository show --name "$ACR_NAME" --image "$IMAGE_NAME:$IMAGE_TAG" --query "createdTime" --output tsv 2>/dev/null || echo "")

        if [ -n "$EXISTING_CREATED" ]; then
          echo "Existing image created: $EXISTING_CREATED"
          echo "Proceeding with rebuild to ensure latest code..."
        fi
      fi

      # Build and push the image
      echo "Building and pushing container image..."
      echo "Command: az acr build --registry $ACR_NAME --image $IMAGE_NAME:$IMAGE_TAG --file $DOCKERFILE_PATH $SOURCE_LOCATION#$BRANCH"

      # Run the build with proper error handling
      MAX_RETRIES=3
      RETRY_COUNT=0

      while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "Build attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."

        if az acr build \
          --registry "$ACR_NAME" \
          --image "$IMAGE_NAME:$IMAGE_TAG" \
          --file "$DOCKERFILE_PATH" \
          "$SOURCE_LOCATION#$BRANCH" \
          --verbose; then
          echo "✓ Build completed successfully!"
          break
        else
          RETRY_COUNT=$((RETRY_COUNT + 1))
          if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Build failed, retrying in 30 seconds..."
            sleep 30
          else
            echo "❌ Build failed after $MAX_RETRIES attempts"
            exit 1
          fi
        fi
      done

      # Verify the image exists
      echo "Verifying image was pushed..."
      sleep 10  # Brief wait for image to be available

      if az acr repository show --name "$ACR_NAME" --image "$IMAGE_NAME:$IMAGE_TAG" >/dev/null 2>&1; then
        echo "✓ Image $IMAGE_NAME:$IMAGE_TAG successfully available in registry"
        echo "Available tags:"
        az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --output table
      else
        echo "❌ Image verification failed"
        echo "Available repositories:"
        az acr repository list --name "$ACR_NAME" --output table || true
        exit 1
      fi

      echo "=== Container Image Build Complete! ==="
      echo "Registry: $LOGIN_SERVER"
      echo "Image: $IMAGE_NAME:$IMAGE_TAG"
      echo "Full Image Name: $LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
      echo "✓ Container image is ready for deployment!"
    '''
  }
  dependsOn: [
    acrPushRoleAssignment
    acrContributorRoleAssignment
    resourceGroupReaderRoleAssignment
  ]
}

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

@description('The deployment script name')
output buildScriptName string = buildScript.name

@description('The resource ID of the App Service ACR role assignment')
output appServiceRoleAssignmentId string = appServiceAcrPullRoleAssignment.id
