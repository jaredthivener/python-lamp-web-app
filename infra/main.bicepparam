using './main.bicep'

// =============================================================================
// Azure Infrastructure Parameters for Lamp Web App
// =============================================================================
// This parameter file defines the configuration for deploying the lamp web app
// infrastructure to Azure using Bicep.
// =============================================================================

// Environment Configuration
param environmentName = 'dev'
param location = 'centralus'
param resourceGroupName = 'rg-lamp-web-app-dev'

// App Service Configuration
param appServicePlanSku = 'B1' // Using B1 for better performance than F1
param appPort = '8000'

// Container Registry Configuration
param containerRegistrySku = 'Basic' // Basic tier is sufficient for development

// PostgreSQL admin password.
// Pull from an env var (set AZURE_POSTGRES_ADMIN_PASSWORD before `azd up` /
// `az deployment sub create`). Do not hard-code secrets in this file.
// The empty default allows `azd down` / `az bicep build` to compile without
// the variable present; the @minLength(16) constraint on the param will
// catch an empty value if an actual deployment is attempted without it set.
param postgresAdminPassword = readEnvironmentVariable('AZURE_POSTGRES_ADMIN_PASSWORD', '')

// Production environment settings (uncomment for production)
// param environmentName = 'prod'
// param appServicePlanSku = 'P1v3'
// param containerRegistrySku = 'Standard'
// param resourceGroupName = 'rg-lamp-web-app-prod'
// param location = 'eastus2' // Consider paired regions for production

// Staging environment settings (uncomment for staging)
// param environmentName = 'staging'
// param appServicePlanSku = 'S1'
// param containerRegistrySku = 'Standard'
// param resourceGroupName = 'rg-lamp-web-app-staging'
