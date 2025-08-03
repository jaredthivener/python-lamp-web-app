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

@description('The resource ID of the user-assigned managed identity for deployment scripts')
param managedIdentityId string

@description('The principal ID of the user-assigned managed identity for deployment scripts')
param managedIdentityPrincipalId string

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
// Role Assignment: Grant Managed Identity ACR Push permissions
// =============================================================================
resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'AcrPush')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Role Assignment: Grant Managed Identity Contributor permissions on ACR
// =============================================================================
resource acrContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'Contributor')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Role Assignment: Grant Managed Identity Reader permissions on Resource Group
// =============================================================================
resource resourceGroupReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentityPrincipalId, 'Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Deployment Script to Build and Push Image
// =============================================================================
resource buildScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'build-push-${take(uniqueString(containerRegistry.id, location, deployment().name), 8)}'
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
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnExpiration'
    forceUpdateTag: uniqueString(containerRegistry.id, deployment().name)
    environmentVariables: [
      {
        name: 'ACR_NAME'
        value: containerRegistry.name
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'SUBSCRIPTION_ID'
        value: subscription().subscriptionId
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

      echo "=== Azure Container Registry Build Script ==="
      echo "Subscription: $SUBSCRIPTION_ID"
      echo "Resource Group: $RESOURCE_GROUP"
      echo "Registry: $ACR_NAME"
      echo "Source: $SOURCE_URL"
      echo "Image: $IMAGE_NAME:$IMAGE_TAG"
      echo "Branch: $SOURCE_BRANCH"
      echo "Dockerfile: $DOCKERFILE_PATH"
      
      # Set the subscription context
      echo "Setting subscription context..."
      az account set --subscription "$SUBSCRIPTION_ID"
      
      # Verify current context
      echo "Current context:"
      az account show --query "{subscriptionId:id, user:user.name}" -o table
      
      # Brief wait for role assignments to propagate
      echo "Waiting for role assignments to propagate..."
      sleep 30
      
      # Since ACR is already created by Bicep, let's directly verify access
      echo "Verifying ACR exists and is accessible..."
      if ! az acr show --name "$ACR_NAME" >/dev/null 2>&1; then
        echo "❌ ERROR: Cannot access ACR."
        echo "Trying without resource group parameter..."
        if ! az acr show --name "$ACR_NAME" >/dev/null 2>&1; then
          echo "❌ ERROR: ACR not found: $ACR_NAME"
          echo "Available ACRs:"
          az acr list --query "[].{name:name, resourceGroup:resourceGroup}" -o table || true
          exit 1
        fi
      fi
      
      # Get ACR details
      ACR_STATE=$(az acr show --name "$ACR_NAME" --query "provisioningState" -o tsv)
      LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query "loginServer" -o tsv)
      
      echo "✓ ACR found: $ACR_NAME"
      echo "✓ Provisioning State: $ACR_STATE"
      echo "✓ Login Server: $LOGIN_SERVER"
      
      # For ACR Tasks, we don't need to login explicitly
      echo "✓ Ready to proceed with ACR Tasks build"

      # Build and push using ACR build directly from GitHub
      echo "Starting container image build using ACR Tasks..."
      echo "Building image: $IMAGE_NAME:$IMAGE_TAG from $SOURCE_URL#$SOURCE_BRANCH"
      
      # Use ACR build to build from the source repository with retry logic
      # ACR Tasks uses the managed identity automatically for authentication
      RETRY_COUNT=0
      MAX_BUILD_RETRIES=3
      
      while [ $RETRY_COUNT -lt $MAX_BUILD_RETRIES ]; do
        echo "Build attempt $((RETRY_COUNT + 1))/$MAX_BUILD_RETRIES"
        
        if az acr build \
          --registry "$ACR_NAME" \
          --image "$IMAGE_NAME:$IMAGE_TAG" \
          --file "$DOCKERFILE_PATH" \
          --platform linux/amd64 \
          "$SOURCE_URL#$SOURCE_BRANCH"; then
          echo "✓ Build completed successfully!"
          break
        else
          RETRY_COUNT=$((RETRY_COUNT + 1))
          if [ $RETRY_COUNT -lt $MAX_BUILD_RETRIES ]; then
            echo "⚠️  Build failed, retrying in 30 seconds... ($RETRY_COUNT/$MAX_BUILD_RETRIES)"
            sleep 30
          else
            echo "❌ Build failed after $MAX_BUILD_RETRIES attempts"
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
