#!/bin/bash

# Azure Infrastructure Setup Script for GitHub Actions
# This script helps you set up the Azure Service Principal and OIDC federation for GitHub Actions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required tools are installed
check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        exit 1
    fi

    print_success "Prerequisites check passed!"
}

# Get user inputs
get_inputs() {
    print_info "Gathering required information..."

    # Get current subscription
    CURRENT_SUBSCRIPTION=$(az account show --query id --output tsv 2>/dev/null || echo "")

    if [ -z "$CURRENT_SUBSCRIPTION" ]; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    print_info "Current Azure subscription: $CURRENT_SUBSCRIPTION"
    read -p "Use this subscription? (y/n): " USE_CURRENT

    if [ "$USE_CURRENT" != "y" ]; then
        read -p "Enter your Azure subscription ID: " SUBSCRIPTION_ID
        az account set --subscription "$SUBSCRIPTION_ID"
    else
        SUBSCRIPTION_ID="$CURRENT_SUBSCRIPTION"
    fi

    read -p "Enter your GitHub username: " GITHUB_USERNAME
    read -p "Enter your GitHub repository name (default: python-lamp-web-app): " REPO_NAME
    REPO_NAME=${REPO_NAME:-python-lamp-web-app}

    read -p "Enter a name for the Service Principal (default: gh-actions-lamp-web-app): " SP_NAME
    SP_NAME=${SP_NAME:-gh-actions-lamp-web-app}

    FULL_REPO_NAME="$GITHUB_USERNAME/$REPO_NAME"

    print_info "Configuration:"
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    echo "  Repository: $FULL_REPO_NAME"
    echo "  Service Principal: $SP_NAME"

    read -p "Continue with this configuration? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        print_info "Setup cancelled."
        exit 0
    fi
}

# Create Service Principal
create_service_principal() {
    print_info "Creating Service Principal..."

    # Create the service principal
    SP_OUTPUT=$(az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role Contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --query '{clientId: appId, tenantId: tenant, subscriptionId: subscriptionId}' \
        --output json)

    CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
    TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenantId')

    if [ "$CLIENT_ID" == "null" ] || [ -z "$CLIENT_ID" ]; then
        print_error "Failed to create Service Principal"
        exit 1
    fi

    print_success "Service Principal created successfully!"
    echo "  Client ID: $CLIENT_ID"
    echo "  Tenant ID: $TENANT_ID"
}

# Create OIDC federation
create_oidc_federation() {
    print_info "Creating OIDC federated credentials..."

    # Create federated credential for main branch
    az ad app federated-credential create \
        --id "$CLIENT_ID" \
        --parameters "{
            \"name\": \"github-actions-main\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"repo:$FULL_REPO_NAME:ref:refs/heads/main\",
            \"description\": \"GitHub Actions for main branch\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" \
        --output none

    print_success "OIDC federation for main branch created!"

    # Create federated credential for pull requests
    read -p "Create OIDC federation for pull requests? (y/n): " CREATE_PR_FEDERATION
    if [ "$CREATE_PR_FEDERATION" == "y" ]; then
        az ad app federated-credential create \
            --id "$CLIENT_ID" \
            --parameters "{
                \"name\": \"github-actions-pr\",
                \"issuer\": \"https://token.actions.githubusercontent.com\",
                \"subject\": \"repo:$FULL_REPO_NAME:pull_request\",
                \"description\": \"GitHub Actions for pull requests\",
                \"audiences\": [\"api://AzureADTokenExchange\"]
            }" \
            --output none

        print_success "OIDC federation for pull requests created!"
    fi
}

# Display final instructions
display_instructions() {
    print_success "Setup completed successfully!"
    echo
    print_info "Add these secrets to your GitHub repository:"
    echo "  Go to: https://github.com/$FULL_REPO_NAME/settings/secrets/actions"
    echo
    echo "  AZURE_CLIENT_ID: $CLIENT_ID"
    echo "  AZURE_TENANT_ID: $TENANT_ID"
    echo "  AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    echo
    print_info "Your GitHub Actions workflow is ready to deploy Azure infrastructure!"
    echo
    print_warning "Keep these values secure and never commit them to your repository."
}

# Main execution
main() {
    echo "🚀 Azure Infrastructure Setup for GitHub Actions"
    echo "=============================================="
    echo

    check_prerequisites
    get_inputs
    create_service_principal
    create_oidc_federation
    display_instructions

    print_success "Setup complete! 🎉"
}

# Run the script
main "$@"
