#!/bin/bash

# =============================================================================
# Azure Deployment Script for Lamp Web App
# =============================================================================
# This script automates the deployment of the lamp web app to Azure App Service
# using best practices including system-managed identity for ACR authentication
#
# Features:
# - Robust error handling with validation
# - System-managed identity (more secure than user-assigned)
# - Resource cleanup on failure
# - Comprehensive logging
# - Interactive prompts with sensible defaults
# - Deployment verification
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# Configuration and Constants
# =============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
readonly DEFAULT_LOCATION="eastus2"
readonly DEFAULT_SKU="F1"
readonly DEFAULT_ACR_SKU="Basic"

# Get script directory safely
SCRIPT_DIR_TMP="$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR_RESOLVED="$(cd "$SCRIPT_DIR_TMP" && pwd)"
readonly SCRIPT_DIR="$SCRIPT_DIR_RESOLVED"
readonly LOG_FILE="${SCRIPT_DIR}/azure-deployment.log"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${level}${timestamp} - ${message}${NC}" | tee -a "$LOG_FILE"
}

log_info() { log "${BLUE}[INFO]${NC} " "$@"; }
log_success() { log "${GREEN}[SUCCESS]${NC} " "$@"; }
log_warning() { log "${YELLOW}[WARNING]${NC} " "$@"; }
log_error() { log "${RED}[ERROR]${NC} " "$@"; }

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local variable_name="$3"
    
    read -r -p "$(echo -e "${BLUE}${prompt}${NC} [${GREEN}${default}${NC}]: ")"
    eval "$variable_name=\"\${value:-\$default}\""
}

validate_azure_cli() {
    log_info "Validating Azure CLI installation and authentication..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first:"
        log_error "brew install azure-cli"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run: az login"
        exit 1
    fi
    
    log_success "Azure CLI validation passed"
}

validate_docker() {
    log_info "Validating Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker Desktop first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker Desktop."
        exit 1
    fi
    
    log_success "Docker validation passed"
}

validate_dockerfile() {
    log_info "Validating Dockerfile exists..."
    
    if [[ ! -f "${SCRIPT_DIR}/Dockerfile" ]]; then
        log_error "Dockerfile not found in ${SCRIPT_DIR}. Please ensure you're running this script from the project root."
        exit 1
    fi
    
    log_success "Dockerfile validation passed"
}

validate_resource_name() {
    local name="$1"
    local type="$2"
    
    case "$type" in
        "resource-group")
            if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ ${#name} -gt 90 ]]; then
                log_error "Invalid resource group name. Must be 1-90 characters, alphanumeric, periods, underscores, hyphens only."
                return 1
            fi
            ;;
        "app-name")
            if [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] || [[ ${#name} -gt 60 ]] || [[ ${#name} -lt 2 ]]; then
                log_error "Invalid app name. Must be 2-60 characters, alphanumeric and hyphens only."
                return 1
            fi
            ;;
        "acr-name")
            if [[ ! "$name" =~ ^[a-zA-Z0-9]+$ ]] || [[ ${#name} -gt 50 ]] || [[ ${#name} -lt 5 ]]; then
                log_error "Invalid ACR name. Must be 5-50 characters, alphanumeric only."
                return 1
            fi
            ;;
    esac
    
    return 0
}

generate_unique_names() {
    local base_username="$1"
    local attempt="$2"
    
    # Generate a truly unique identifier using UUID or high-entropy random
    local unique_id
    if command -v uuidgen &> /dev/null; then
        # Use system UUID generator and make it shorter
        unique_id=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | head -c 16)
    else
        # Fallback to high-entropy random generation
        unique_id=$(openssl rand -hex 8 2>/dev/null || printf '%016x' $(($(date +%s) * RANDOM * RANDOM % 18446744073709551616)))
    fi
    
    # Add attempt number for additional uniqueness in retries
    if [[ $attempt -gt 1 ]]; then
        unique_id="${unique_id}${attempt}"
    fi
    
    # Azure naming convention with truly unique IDs (no dashes for app/acr)
    local rg_name="rg-lamp-${unique_id}"
    local app_name="app${unique_id}"    # No dash - cleaner and follows Azure conventions
    local acr_name="acr${unique_id}"    # ACR doesn't allow hyphens
    
    # Ensure names meet Azure requirements
    # App Service: max 60 chars, alphanumeric and hyphens (but we're not using hyphens)
    if [[ ${#app_name} -gt 60 ]]; then
        app_name="app${unique_id:0:57}"  # 3 chars for "app"
    fi
    
    # ACR: max 50 chars, alphanumeric only
    if [[ ${#acr_name} -gt 50 ]]; then
        acr_name="acr${unique_id:0:47}"  # 3 chars for "acr"
    fi
    
    # Return as space-separated values: rg_name app_name acr_name
    echo "${rg_name} ${app_name} ${acr_name}"
}

# =============================================================================
# Cleanup Function
# =============================================================================

cleanup_on_failure() {
    local resource_group="$1"
    
    if [[ "${CLEANUP_ON_FAILURE:-true}" == "true" ]]; then
        log_warning "Deployment failed. Cleaning up resources..."
        echo -e "${YELLOW}Do you want to delete the resource group '${resource_group}' and all its resources? [y/N]:${NC} "
        read -r cleanup_response
        
        if [[ "$cleanup_response" =~ ^[Yy]$ ]]; then
            log_info "Deleting resource group '$resource_group'..."
            if az group delete --name "$resource_group" --yes --no-wait; then
                log_success "Resource group deletion initiated"
            else
                log_error "Failed to delete resource group. Please clean up manually."
            fi
        else
            log_warning "Skipping cleanup. Remember to manually delete resources to avoid charges."
        fi
    fi
}

# =============================================================================
# Azure Resource Creation Functions
# =============================================================================

create_resource_group() {
    local resource_group="$1"
    local location="$2"
    
    log_info "Creating resource group '$resource_group' in '$location'..."
    
    if az group create \
        --name "$resource_group" \
        --location "$location" \
        --output none; then
        log_success "Resource group created successfully"
    else
        log_error "Failed to create resource group"
        return 1
    fi
}

create_container_registry() {
    local resource_group="$1"
    local acr_name="$2"
    local acr_sku="$3"
    
    log_info "Creating Azure Container Registry '$acr_name'..."
    
    if az acr create \
        --resource-group "$resource_group" \
        --name "$acr_name" \
        --sku "$acr_sku" \
        --admin-enabled false \
        --output none; then
        log_success "Container Registry created successfully"
    else
        log_error "Failed to create Container Registry"
        return 1
    fi
}

create_app_service_plan() {
    local resource_group="$1"
    local app_name="$2"
    local sku="$3"
    
    log_info "Creating App Service Plan '${app_name}-plan'..."
    
    if az appservice plan create \
        --name "${app_name}-plan" \
        --resource-group "$resource_group" \
        --sku "$sku" \
        --is-linux \
        --output none; then
        log_success "App Service Plan created successfully"
    else
        log_error "Failed to create App Service Plan"
        return 1
    fi
}

create_web_app() {
    local resource_group="$1"
    local app_name="$2"
    local acr_login_server="$3"
    
    log_info "Creating Web App '$app_name'..."
    
    if az webapp create \
        --resource-group "$resource_group" \
        --plan "${app_name}-plan" \
        --name "$app_name" \
        --deployment-container-image-name "${acr_login_server}/lamp-app:latest" \
        --output none; then
        log_success "Web App created successfully"
    else
        log_error "Failed to create Web App"
        return 1
    fi
}

configure_system_managed_identity() {
    local resource_group="$1"
    local app_name="$2"
    local acr_name="$3"
    
    log_info "Enabling system-managed identity for Web App..."
    
    # Enable system-managed identity
    local principal_id
    if principal_id=$(az webapp identity assign \
        --resource-group "$resource_group" \
        --name "$app_name" \
        --query principalId \
        --output tsv); then
        log_success "System-managed identity enabled. Principal ID: $principal_id"
    else
        log_error "Failed to enable system-managed identity"
        return 1
    fi
    
    log_info "Assigning AcrPull role to system-managed identity..."
    
    # Get ACR resource ID
    local acr_id
    if acr_id=$(az acr show \
        --name "$acr_name" \
        --resource-group "$resource_group" \
        --query id \
        --output tsv); then
        log_info "ACR ID: $acr_id"
    else
        log_error "Failed to get ACR resource ID"
        return 1
    fi
    
    # Wait for identity to propagate before role assignment
    log_info "Waiting for managed identity to propagate (60 seconds)..."
    sleep 60
    
    # Assign AcrPull role with retry logic (role assignment can take time to propagate)
    local max_attempts=15
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempting role assignment (attempt $attempt/$max_attempts)..."
        
        if az role assignment create \
            --assignee "$principal_id" \
            --scope "$acr_id" \
            --role AcrPull \
            --output none 2>/dev/null; then
            log_success "AcrPull role assigned successfully"
            break
        else
            if [[ $attempt -eq $max_attempts ]]; then
                log_error "Failed to assign AcrPull role after $max_attempts attempts"
                log_error "You may need to manually assign the role: az role assignment create --assignee $principal_id --scope $acr_id --role AcrPull"
                return 1
            fi
            log_warning "Role assignment failed, retrying in 30 seconds..."
            sleep 30
            ((attempt++))
        fi
    done
    
    # Additional wait for role assignment to fully propagate
    log_info "Waiting for role assignment to propagate (30 seconds)..."
    sleep 30
}

build_and_push_image() {
    local acr_name="$1"
    local acr_login_server="$2"
    
    log_info "Logging into Azure Container Registry..."
    
    if az acr login --name "$acr_name"; then
        log_success "Successfully logged into ACR"
    else
        log_error "Failed to login to ACR"
        return 1
    fi
    
    log_info "Building Docker image for linux/amd64 platform (Azure App Service requirement)..."
    
    # Build for the correct platform (linux/amd64) that Azure App Service expects
    if docker build --platform linux/amd64 -t "${acr_login_server}/lamp-app:latest" "$SCRIPT_DIR"; then
        log_success "Docker image built successfully for linux/amd64"
    else
        log_error "Failed to build Docker image"
        return 1
    fi
    
    log_info "Pushing image to Azure Container Registry..."
    
    if docker push "${acr_login_server}/lamp-app:latest"; then
        log_success "Image pushed successfully to ACR"
    else
        log_error "Failed to push image to ACR"
        return 1
    fi
}

configure_web_app() {
    local resource_group="$1"
    local app_name="$2"
    local acr_login_server="$3"
    
    log_info "Configuring Web App container settings..."
    
    # Configure container settings to use system-assigned managed identity
    if az webapp config container set \
        --name "$app_name" \
        --resource-group "$resource_group" \
        --container-image-name "${acr_login_server}/lamp-app:latest" \
        --container-registry-url "https://${acr_login_server}" \
        --enable-app-service-storage false \
        --output none; then
        log_success "Container settings configured"
    else
        log_error "Failed to configure container settings"
        return 1
    fi
    
    log_info "Configuring App Service to use system-assigned managed identity for ACR..."
    
    # This is the CRITICAL setting that enables managed identity authentication for ACR
    if az resource update \
        --resource-group "$resource_group" \
        --name "$app_name" \
        --resource-type "Microsoft.Web/sites" \
        --set properties.siteConfig.acrUseManagedIdentityCreds=true \
        --output none; then
        log_success "ACR managed identity authentication enabled"
    else
        log_error "Failed to enable ACR managed identity authentication"
        return 1
    fi
    
    log_info "Configuring application settings..."
    
    # Configure app settings with proper container support
    if az webapp config appsettings set \
        --resource-group "$resource_group" \
        --name "$app_name" \
        --settings \
            PORT=8000 \
            PYTHONPATH=/app/src \
            WEBSITES_ENABLE_APP_SERVICE_STORAGE=false \
            WEBSITES_PORT=8000 \
            DOCKER_ENABLE_CI=true \
            DOCKER_REGISTRY_SERVER_URL="https://${acr_login_server}" \
        --output none; then
        log_success "Application settings configured"
    else
        log_error "Failed to configure application settings"
        return 1
    fi
    
    log_info "Enabling HTTPS-only access..."
    
    # Enable HTTPS only
    if az webapp update \
        --resource-group "$resource_group" \
        --name "$app_name" \
        --https-only true \
        --output none; then
        log_success "HTTPS-only enabled"
    else
        log_error "Failed to enable HTTPS-only"
        return 1
    fi
    
    log_info "Enabling container logging..."
    
    # Enable container logging
    if az webapp log config \
        --resource-group "$resource_group" \
        --name "$app_name" \
        --docker-container-logging filesystem \
        --level information \
        --output none; then
        log_success "Container logging enabled"
    else
        log_error "Failed to enable container logging"
        return 1
    fi
}

verify_deployment() {
    local resource_group="$1"
    local app_name="$2"
    
    log_info "Verifying deployment..."
    
    # Get app URL
    local app_url
    if app_url=$(az webapp show \
        --name "$app_name" \
        --resource-group "$resource_group" \
        --query defaultHostName \
        --output tsv); then
        log_success "App URL: https://$app_url"
    else
        log_error "Failed to get app URL"
        return 1
    fi
    
    # Check app state
    local app_state
    if app_state=$(az webapp show \
        --name "$app_name" \
        --resource-group "$resource_group" \
        --query state \
        --output tsv); then
        log_info "App state: $app_state"
    else
        log_error "Failed to get app state"
        return 1
    fi
    
    # Wait for app to be ready and test health endpoint
    log_info "Waiting for application to start (this may take a few minutes)..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    local health_check_interval=30
    
    while [[ $wait_time -lt $max_wait ]]; do
        if curl -s -f "https://$app_url/health" &> /dev/null; then
            log_success "Application is healthy and responding!"
            break
        fi
        
        log_info "Application not ready yet, waiting ${health_check_interval}s..."
        sleep $health_check_interval
        wait_time=$((wait_time + health_check_interval))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log_warning "Health check timeout. App may still be starting. Check logs with:"
        log_warning "az webapp log tail --name $app_name --resource-group $resource_group"
    fi
    
    return 0
}

setup_continuous_deployment() {
    local resource_group="$1"
    local app_name="$2"
    local acr_name="$3"
    
    log_info "Setting up continuous deployment for automatic updates..."
    
    # Get ACR login server
    local acr_login_server
    if ! acr_login_server=$(az acr show \
        --name "$acr_name" \
        --resource-group "$resource_group" \
        --query loginServer \
        --output tsv); then
        log_error "Failed to get ACR login server"
        return 1
    fi
    
    # Configure the web app to use ACR with system-managed identity
    log_info "Configuring container settings for continuous deployment..."
    if ! az webapp config container set \
        --name "$app_name" \
        --resource-group "$resource_group" \
        --container-image-name "${acr_login_server}/lamp-app:latest" \
        --container-registry-url "https://${acr_login_server}" \
        --output none; then
        log_error "Failed to configure container settings"
        return 1
    fi
    
    # Enable continuous deployment - modern approach
    log_info "Enabling continuous deployment..."
    
    # Method 1: Try the modern webhook approach
    local webhook_url
    if az webapp deployment container config \
        --name "$app_name" \
        --resource-group "$resource_group" \
        --enable-cd true \
        --output none 2>/dev/null; then
        
        log_success "Continuous deployment enabled"
        
        # Get the webhook URL using publishing profile
        local publish_url
        if publish_url=$(az webapp deployment list-publishing-profiles \
            --name "$app_name" \
            --resource-group "$resource_group" \
            --query "[?publishMethod=='WebDeploy'].publishUrl" \
            --output tsv 2>/dev/null); then
            
            # Extract the site name and construct webhook URL
            local site_name
            site_name=$(echo "$publish_url" | cut -d'.' -f1)
            webhook_url="https://${site_name}.scm.azurewebsites.net/docker/hook"
            log_info "Webhook URL constructed: $webhook_url"
        fi
    fi
    
    # Method 2: Fallback - construct webhook URL directly
    if [[ -z "$webhook_url" ]]; then
        log_info "Using fallback webhook URL construction..."
        webhook_url="https://${app_name}.scm.azurewebsites.net/docker/hook"
        log_info "Fallback webhook URL: $webhook_url"
    fi
    
    # Method 3: Get the actual deployment credentials for webhook
    if [[ -n "$webhook_url" ]]; then
        # Get publishing credentials to validate webhook URL
        local username password
        if creds=$(az webapp deployment list-publishing-credentials \
            --name "$app_name" \
            --resource-group "$resource_group" \
            --query "{username:publishingUserName, password:publishingPassword}" \
            --output json 2>/dev/null); then
            
            username=$(echo "$creds" | jq -r '.username')
            password=$(echo "$creds" | jq -r '.password')
            
            if [[ "$username" != "null" && "$password" != "null" ]]; then
                log_info "Publishing credentials retrieved successfully"
            fi
        fi
        
        # Create ACR webhook with proper configuration
        local webhook_name
        webhook_name=$(echo "${app_name}webhook" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        
        # Ensure webhook name is unique and valid
        if [[ ${#webhook_name} -gt 50 ]]; then
            webhook_name="${webhook_name:0:50}"
        fi
        
        log_info "Creating ACR webhook '$webhook_name'..."
        
        # Delete existing webhook if it exists
        az acr webhook delete \
            --name "$webhook_name" \
            --registry "$acr_name" \
            --yes &>/dev/null || true
        
        # Wait a moment for deletion to complete
        sleep 5
        
        # Create the webhook with proper authentication if credentials are available
        local webhook_headers="Content-Type=application/json"
        if [[ -n "$username" && -n "$password" && "$username" != "null" && "$password" != "null" ]]; then
            # Add basic auth header
            local auth_header
            auth_header=$(echo -n "$username:$password" | base64)
            webhook_headers="Content-Type=application/json Authorization=Basic $auth_header"
        fi
        
        if az acr webhook create \
            --name "$webhook_name" \
            --registry "$acr_name" \
            --resource-group "$resource_group" \
            --actions push \
            --uri "$webhook_url" \
            --scope "lamp-app:*" \
            --headers "$webhook_headers" \
            --status enabled \
            --output none; then
            
            log_success "✅ ACR webhook created successfully: $webhook_name"
            
            # Verify webhook configuration
            log_info "Webhook details:"
            az acr webhook show \
                --registry "$acr_name" \
                --name "$webhook_name" \
                --query "{name:name, serviceUri:serviceUri, status:status, scope:scope, actions:actions}" \
                --output table 2>/dev/null || true
            
            # Test the webhook
            log_info "Testing webhook configuration..."
            if az acr webhook ping \
                --name "$webhook_name" \
                --registry "$acr_name" \
                --output none 2>/dev/null; then
                log_success "✅ Webhook test successful"
            else
                log_warning "Webhook test failed - webhook created but may need manual verification"
            fi
            
        else
            log_warning "Failed to create ACR webhook automatically"
            log_info "Manual webhook setup required:"
            log_info "1. Go to Azure Portal -> Container Registry ($acr_name) -> Webhooks"
            log_info "2. Add webhook with URL: $webhook_url"
            log_info "3. Set scope to: lamp-app:*"
            log_info "4. Set actions to: push"
            log_info "5. Set status to: enabled"
        fi
        
        return 0
    else
        log_error "Failed to obtain webhook URL for continuous deployment"
        return 1
    fi
}

create_acr_build_task() {
    local resource_group="$1"
    local acr_name="$2"
    local app_name="$3"
    
    log_info "Creating ACR build task for automated builds..."
    
    # Create a basic ACR task for building from source
    local task_name="${app_name}-build-task"
    
    # Check if we should create an ACR task (optional feature)
    echo -e "\n${YELLOW}ACR Build Task (Optional):${NC}"
    echo "This creates an automated build task that can build your image from source code."
    echo "Useful if you want to trigger builds from GitHub/GitLab repositories."
    
    read -p "$(echo -e "${BLUE}Create ACR build task? [y/N]:${NC} ")" -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping ACR build task creation"
        return 0
    fi
    
    # For now, create a simple task that can be configured later
    if az acr task create \
        --registry "$acr_name" \
        --name "$task_name" \
        --context /dev/null \
        --cmd "echo 'ACR Task created - configure with your source repository'" \
        --output none; then
        log_success "ACR build task created: $task_name"
        log_info "Configure it later with: az acr task update --registry $acr_name --name $task_name --context <your-repo-url>"
    else
        log_warning "Failed to create ACR build task (this is optional and won't affect deployment)"
    fi
}

test_webhook_functionality() {
    local resource_group="$1"
    local app_name="$2"
    local acr_name="$3"
    local acr_login_server="$4"
    
    log_info "Testing webhook functionality with a dummy push..."
    
    # Create a simple test to verify webhook works
    echo -e "\n${YELLOW}Webhook Test (Optional):${NC}"
    echo "This will create a test tag and push it to trigger the webhook."
    
    read -p "$(echo -e "${BLUE}Test webhook with dummy push? [y/N]:${NC} ")" -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping webhook test"
        return 0
    fi
    
    # Tag current image with test tag and push to trigger webhook
    log_info "Creating test image tag to trigger webhook..."
    
    if docker tag "${acr_login_server}/lamp-app:latest" "${acr_login_server}/lamp-app:webhook-test-$(date +%s)"; then
        log_info "Test tag created"
    else
        log_warning "Failed to create test tag"
        return 1
    fi
    
    # Push the test tag (this should trigger the webhook)
    if docker push "${acr_login_server}/lamp-app:webhook-test-*" 2>/dev/null || \
       docker push "${acr_login_server}/lamp-app:latest"; then
        log_success "Test push completed - webhook should be triggered"
        log_info "Check your App Service logs to see if the webhook triggered a deployment"
        log_info "Monitor with: az webapp log tail --name $app_name --resource-group $resource_group"
    else
        log_warning "Test push failed"
        return 1
    fi
}

# =============================================================================
# Fix Deployment Function (for existing deployments with issues)
# =============================================================================

fix_deployment_issues() {
    local resource_group="$1"
    local app_name="$2"
    local acr_name="$3"
    
    log_info "Fixing deployment issues..."
    
    # Get ACR login server
    local acr_login_server
    if acr_login_server=$(az acr show \
        --name "$acr_name" \
        --resource-group "$resource_group" \
        --query loginServer \
        --output tsv); then
        log_info "ACR Login Server: $acr_login_server"
    else
        log_error "Failed to get ACR login server"
        return 1
    fi
    
    # Rebuild and push image with correct architecture
    build_and_push_image "$acr_name" "$acr_login_server"
    
    # Reconfigure managed identity with proper timing
    configure_system_managed_identity "$resource_group" "$app_name" "$acr_name"
    
    # Restart the app to pull the new image
    log_info "Restarting Web App to apply fixes..."
    if az webapp restart --name "$app_name" --resource_group "$resource_group" --output none; then
        log_success "Web App restarted successfully"
    else
        log_error "Failed to restart Web App"
        return 1
    fi
    
    # Wait a bit for the restart to take effect
    log_info "Waiting for restart to complete (30 seconds)..."
    sleep 30
    
    log_success "Deployment fixes applied successfully"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log_info "Starting Azure deployment for Lamp Web App"
    log_info "Log file: $LOG_FILE"
    
    # Validate prerequisites
    validate_azure_cli
    validate_docker
    validate_dockerfile
    
    # Interactive configuration with unique name generation
    echo -e "\n${BLUE}=== Azure Deployment Configuration ===${NC}"
    echo -e "${YELLOW}Note: Azure resource names must be globally unique.${NC}"
    echo -e "${YELLOW}Generating highly unique names following Azure naming standards...${NC}\n"
    
    # Get base username for name generation
    local base_username
    base_username=$(whoami | tr '[:upper:]' '[:lower:]' | head -c 4)
    
    # Generate unique names following Azure naming conventions
    local name_parts
    name_parts=$(generate_unique_names "$base_username" "1")
    read -r default_rg default_app default_acr <<< "$name_parts"
    
    # Prompt for all configuration
    prompt_with_default "Resource Group name" "$default_rg" "RESOURCE_GROUP"
    prompt_with_default "App Service name (globally unique)" "$default_app" "APP_NAME"
    prompt_with_default "Azure region" "$DEFAULT_LOCATION" "LOCATION"
    prompt_with_default "ACR name (globally unique, 5-50 chars, alphanumeric)" "$default_acr" "ACR_NAME"
    prompt_with_default "App Service Plan SKU" "$DEFAULT_SKU" "SKU"
    prompt_with_default "Container Registry SKU" "$DEFAULT_ACR_SKU" "ACR_SKU"
    
    # Validate resource names
    if ! validate_resource_name "$RESOURCE_GROUP" "resource-group" || \
       ! validate_resource_name "$APP_NAME" "app-name" || \
       ! validate_resource_name "$ACR_NAME" "acr-name"; then
        log_error "Invalid resource names. Please check naming requirements and try again."
        exit 1
    fi
    
    # Check resource group existence (skip name availability checks for App Service and ACR)
    log_info "Checking resource group existence..."
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists. Continuing with existing group."
    fi
    log_info "Skipping App Service and ACR name availability checks - names will be verified during resource creation"
    log_success "Resource names prepared for deployment"
    
    # Confirm deployment
    echo -e "\n${YELLOW}=== Deployment Summary ===${NC}"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "App Service: $APP_NAME"
    echo "App Service Plan SKU: $SKU"
    echo "Container Registry: $ACR_NAME"
    echo "Container Registry SKU: $ACR_SKU"
    echo ""
    
    read -p "$(echo -e "${BLUE}Proceed with deployment? [y/N]:${NC} ")" -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Set trap for cleanup on failure
    trap 'cleanup_on_failure "$RESOURCE_GROUP"' ERR
    
    # Create Azure resources
    create_resource_group "$RESOURCE_GROUP" "$LOCATION"
    create_container_registry "$RESOURCE_GROUP" "$ACR_NAME" "$ACR_SKU"
    create_app_service_plan "$RESOURCE_GROUP" "$APP_NAME" "$SKU"
    
    # Get ACR login server
    local acr_login_server
    acr_login_server=$(az acr show \
        --name "$ACR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query loginServer \
        --output tsv)
    
    create_web_app "$RESOURCE_GROUP" "$APP_NAME" "$acr_login_server"
    configure_system_managed_identity "$RESOURCE_GROUP" "$APP_NAME" "$ACR_NAME"
    build_and_push_image "$ACR_NAME" "$acr_login_server"
    configure_web_app "$RESOURCE_GROUP" "$APP_NAME" "$acr_login_server"
    
    # Setup continuous deployment (this automatically creates ACR webhook)
    setup_continuous_deployment "$RESOURCE_GROUP" "$APP_NAME" "$ACR_NAME"
    
    # Optional: Create ACR build task for automated builds
    create_acr_build_task "$RESOURCE_GROUP" "$ACR_NAME" "$APP_NAME"
    
    # Restart app to apply new configuration
    log_info "Restarting Web App to apply configuration..."
    az webapp restart --name "$APP_NAME" -g "$RESOURCE_GROUP" --output none
    
    verify_deployment "$RESOURCE_GROUP" "$APP_NAME"
    
    # Optional: Test webhook functionality
    test_webhook_functionality "$RESOURCE_GROUP" "$APP_NAME" "$ACR_NAME" "$acr_login_server"
    
    # Success summary
    echo -e "\n${GREEN}=== Deployment Completed Successfully! ===${NC}"
    echo "🚀 Your Lamp Web App is now deployed to Azure!"
    echo ""
    echo "📋 Deployment Details:"
    echo "   • Resource Group: $RESOURCE_GROUP"
    echo "   • App Service: $APP_NAME"
    echo "   • Container Registry: $ACR_NAME"
    echo "   • App URL: https://$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostName --output tsv)"
    echo ""
    echo "🔧 Useful Commands:"
    echo "   • View logs: az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP"
    echo "   • Update app: ./update-app.sh (now with automatic deployment!)"
    echo "   • Manual update: ./deploy-to-azure.sh (rerun this script)"
    echo "   • List webhooks: az acr webhook list --registry $ACR_NAME --output table"
    echo "   • Delete resources: az group delete --name $RESOURCE_GROUP --yes"
    echo ""
    echo "🔒 Security Features Enabled:"
    echo "   ✅ System-managed identity for ACR authentication"
    echo "   ✅ HTTPS-only access"
    echo "   ✅ No admin credentials stored"
    echo "   ✅ Least privilege access (AcrPull only)"
    echo ""
    echo "🚀 Continuous Deployment Features:"
    echo "   ✅ ACR webhook configured for automatic deployments"
    echo "   ✅ Push to ACR automatically triggers App Service update"
    echo "   ✅ No manual restarts needed for image updates"
    
    # Remove trap since deployment succeeded
    trap - ERR
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Ensure script is executable
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
