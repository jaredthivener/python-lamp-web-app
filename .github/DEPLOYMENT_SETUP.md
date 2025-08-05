# Azure Infrastructure Deployment Setup

This guide will help you set up GitHub Actions to automatically deploy your Azure infrastructure using Azure Developer CLI (azd).

## Prerequisites

1. Azure subscription with appropriate permissions
2. GitHub repository with your code
3. Azure CLI installed locally (for initial setup)

## 1. Create Azure Service Principal with OIDC

### Option A: Using Azure CLI (Recommended)

1. **Login to Azure:**

   ```bash
   az login
   az account set --subscription "YOUR_SUBSCRIPTION_ID"
   ```

2. **Create Service Principal with OIDC:**

   ```bash
   # Replace with your values
   SUBSCRIPTION_ID="your-subscription-id"
   RESOURCE_GROUP="rg-lamp-web-app-dev"  # Or your preferred RG name
   APP_NAME="gh-actions-lamp-web-app"
   REPO_NAME="your-github-username/python-lamp-web-app"

   # Create service principal
   az ad sp create-for-rbac \
     --name $APP_NAME \
     --role Contributor \
     --scopes /subscriptions/$SUBSCRIPTION_ID \
     --sdk-auth

   # Note the output - you'll need the clientId, tenantId, and subscriptionId
   ```

3. **Configure OIDC Federation:**

   ```bash
   # Get the Application ID from the previous step
   APP_ID="your-client-id-from-previous-step"

   # Create federated credential for main branch
   az ad app federated-credential create \
     --id $APP_ID \
     --parameters '{
       "name": "github-actions-main",
       "issuer": "https://token.actions.githubusercontent.com",
       "subject": "repo:'$REPO_NAME':ref:refs/heads/main",
       "description": "GitHub Actions for main branch",
       "audiences": ["api://AzureADTokenExchange"]
     }'

   # Create federated credential for pull requests (optional)
   az ad app federated-credential create \
     --id $APP_ID \
     --parameters '{
       "name": "github-actions-pr",
       "issuer": "https://token.actions.githubusercontent.com",
       "subject": "repo:'$REPO_NAME':pull_request",
       "description": "GitHub Actions for pull requests",
       "audiences": ["api://AzureADTokenExchange"]
     }'
   ```

### Option B: Using Azure Portal

1. Go to **Azure Active Directory** > **App registrations**
2. Click **New registration**
3. Name: `gh-actions-lamp-web-app`
4. Click **Register**
5. Note the **Application (client) ID** and **Directory (tenant) ID**
6. Go to **Certificates & secrets** > **Federated credentials**
7. Click **Add credential**
8. Select **GitHub Actions deploying Azure resources**
9. Fill in your GitHub details:
   - Organization: `your-github-username`
   - Repository: `python-lamp-web-app`
   - Entity type: `Branch`
   - GitHub branch name: `main`
10. Click **Add**

## 2. Assign Azure Permissions

1. **Assign Contributor role to Service Principal:**

   ```bash
   # Get your subscription ID
   SUBSCRIPTION_ID=$(az account show --query id --output tsv)

   # Assign Contributor role
   az role assignment create \
     --assignee $APP_ID \
     --role Contributor \
     --scope /subscriptions/$SUBSCRIPTION_ID
   ```

## 3. Configure GitHub Secrets

In your GitHub repository, go to **Settings** > **Secrets and variables** > **Actions** and add these secrets:

| Secret Name             | Value                               | Description                        |
| ----------------------- | ----------------------------------- | ---------------------------------- |
| `AZURE_CLIENT_ID`       | Application (client) ID from step 1 | Service Principal client ID        |
| `AZURE_TENANT_ID`       | Directory (tenant) ID from step 1   | Azure AD tenant ID                 |
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID          | Target subscription for deployment |

## 4. Configure GitHub Environments (Optional but Recommended)

1. Go to **Settings** > **Environments**
2. Create environments: `dev`, `staging`, `prod`
3. For each environment:
   - Add protection rules (required reviewers for prod)
   - Add environment-specific secrets if needed

## 5. Test the Deployment

1. **Manual trigger:**

   - Go to **Actions** tab in GitHub
   - Select "Deploy Azure Infrastructure"
   - Click "Run workflow"
   - Select environment (dev/staging/prod)
   - Click "Run workflow"

2. **Automatic trigger:**
   - Make a change to files in `infra/` folder
   - Push to main branch
   - Workflow will trigger automatically

## 6. Environment-Specific Configuration

### Development Environment

- Uses `B1` App Service Plan (Basic tier)
- Basic Container Registry
- Minimal cost configuration

### Production Environment

To deploy to production:

1. **Update `infra/main.bicepparam`:**

   ```bicep
   // Uncomment and modify for production
   param environmentName = 'prod'
   param appServicePlanSku = 'P1v3'
   param containerRegistrySku = 'Standard'
   param resourceGroupName = 'rg-lamp-web-app-prod'
   param location = 'eastus2'
   ```

2. **Create production secrets** in GitHub (if different from dev)

## 7. Monitoring and Troubleshooting

### View Deployment Logs

1. Go to **Actions** tab in GitHub
2. Click on the workflow run
3. Expand job steps to see detailed logs

### Azure Portal Verification

1. Check Resource Groups in Azure Portal
2. Verify all resources are created correctly
3. Check App Service logs if application deployment fails

### Common Issues

1. **Permission Errors:**

   - Verify Service Principal has Contributor role
   - Check that OIDC federation is configured correctly

2. **Resource Conflicts:**

   - Ensure resource names are unique
   - Check if resources already exist in the subscription

3. **Quota Limits:**
   - Verify your subscription has enough quota for the resources
   - Consider using different regions if quotas are exceeded

## 8. Security Best Practices

- ✅ Use OIDC instead of Service Principal secrets
- ✅ Scope permissions to specific resource groups when possible
- ✅ Use environment protection rules for production deployments
- ✅ Regular review of federated credentials
- ✅ Monitor deployment logs for security events

## 9. Cost Management

- The workflow includes cost-effective resource sizing for development
- Monitor Azure costs regularly
- Consider using Azure Cost Management alerts
- Clean up unused resources in dev/staging environments

## Next Steps

1. Complete the setup steps above
2. Test a deployment to the dev environment
3. Customize the infrastructure parameters for your needs
4. Set up monitoring and alerting for your deployed resources
5. Consider adding integration tests to the workflow
