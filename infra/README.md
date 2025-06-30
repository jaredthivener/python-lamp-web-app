# Azure Infrastructure for Lamp Web App - Modular Bicep Architecture

## Overview
This directory contains the modular Bicep infrastructure code for deploying the Lamp Web App to Azure. The architecture has been refactored from a monolithic structure to a modular design that eliminates cyclic dependencies and follows Azure best practices.

## Architecture

### Main Template
- **File**: `main.bicep`
- **Scope**: Subscription level
- **Purpose**: Orchestrates the deployment of all modules and creates the resource group

### Modules

#### 1. Monitoring Module (`modules/monitoring.bicep`)
- **Resources**:
  - Log Analytics Workspace
  - Application Insights
- **Purpose**: Provides monitoring and observability for the application
- **Dependencies**: None

#### 2. Managed Identity Module (`modules/managed-identity.bicep`)
- **Resources**:
  - User-Assigned Managed Identity
- **Purpose**: Provides secure authentication for App Service to access ACR and other Azure resources
- **Dependencies**: None

#### 3. ACR Module (`modules/acr.bicep`)
- **Resources**:
  - Azure Container Registry
- **Purpose**: Stores Docker container images
- **Dependencies**: None

#### 4. App Service Module (`modules/appservice.bicep`)
- **Resources**:
  - App Service Plan (Linux)
  - App Service (Web App) with container support
  - Diagnostic settings
- **Purpose**: Hosts the web application
- **Dependencies**: Monitoring module (for Application Insights), ACR module (for container registry login server), Managed Identity module (for authentication)

#### 5. ACR Integration Module (`modules/acr-integration.bicep`)
- **Resources**:
  - Role assignment (AcrPull for the managed identity)
  - Container Registry webhook for continuous deployment
- **Purpose**: Establishes the security and deployment integration between ACR and App Service
- **Dependencies**: ACR module, App Service module, and Managed Identity module

## Deployment Order
The modules are deployed in the following order (automatically handled by Bicep dependency resolution):

1. **Resource Group** (created by main template)
2. **Monitoring Module** (no dependencies)
3. **Managed Identity Module** (no dependencies)
4. **ACR Module** (no dependencies)
5. **App Service Module** (depends on Monitoring, ACR, and Managed Identity outputs)
6. **ACR Integration Module** (depends on ACR, App Service, and Managed Identity outputs)

## Key Features

### Security
- User-assigned managed identity for App Service (more secure and predictable than system-assigned)
- AcrPull role assignment with least privilege access
- HTTPS-only access enforced
- No admin credentials stored
- Secure parameter handling for webhook configuration

### Monitoring
- Application Insights with workspace-based configuration
- Log Analytics workspace for centralized logging
- Diagnostic settings for App Service logs and metrics

### Continuous Deployment
- ACR webhook configured for automatic deployment on image push
- Container-based deployment with managed identity authentication

## Deployment

### Prerequisites
- Azure CLI installed and authenticated
- Bicep CLI installed

### Deploy
```bash
# Validate the deployment
az deployment sub validate --location eastus2 --template-file infra/main.bicep --parameters infra/main.parameters.json

# Deploy to Azure
az deployment sub create --location eastus2 --template-file infra/main.bicep --parameters infra/main.parameters.json
```

### Parameters
The deployment can be customized using the following parameters:
- `environmentName`: Environment name (e.g., dev, staging, prod)
- `location`: Azure region for deployment
- `appServicePlanSku`: SKU for the App Service Plan
- `containerRegistrySku`: SKU for the Container Registry
- `appPort`: Port number the application listens on

## Architecture Benefits

### Resolved Identity Timing Issue
The original architecture had a timing problem where the App Service's system-assigned managed identity wasn't available until after the App Service was fully deployed, but it was needed to configure the ACR role assignment and webhook. This has been resolved by:
1. Creating a separate user-assigned managed identity first
2. Assigning this identity to the App Service during its creation
3. Using this identity for ACR authentication and role assignments
4. This approach ensures the identity is available when needed for ACR integration

### Improved Maintainability
- Each module has a single responsibility
- Modules can be tested and validated independently
- Changes to one component don't affect others
- Clear interface definitions between modules

### Reusability
- Modules can be reused across different environments
- Easy to extend with additional modules (e.g., Key Vault, Virtual Network)
- Parameterized for different deployment scenarios

## File Structure
```
infra/
├── main.bicep                      # Main orchestration template
├── main.parameters.json            # Parameter file for deployment
└── modules/
    ├── monitoring.bicep            # Log Analytics + Application Insights
    ├── managed-identity.bicep      # User-Assigned Managed Identity
    ├── acr.bicep                   # Azure Container Registry
    ├── appservice.bicep            # App Service Plan + App Service
    └── acr-integration.bicep       # Role assignment + Webhook
```
