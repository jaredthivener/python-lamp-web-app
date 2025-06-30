using './main.bicep'

// =============================================================================
// Azure Infrastructure Parameters for Lamp Web App
// =============================================================================
// This parameter file defines the configuration for deploying the lamp web app
// infrastructure to Azure using Bicep.
// =============================================================================

// Environment Configuration
param environmentName = 'dev'
param location = 'eastus2'
param resourceGroupName = 'rg-lamp-web-app-dev'

// App Service Configuration
param appServicePlanSku = 'B1' // Using B1 for better performance than F1
param appPort = '8000'

// Container Registry Configuration
param containerRegistrySku = 'Basic' // Basic tier is sufficient for development

// Optional: Override for production environment
// param environmentName = 'prod'
// param appServicePlanSku = 'P1v3'
// param containerRegistrySku = 'Standard'
// param resourceGroupName = 'rg-lamp-web-app-prod'
