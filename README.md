# 🪔 Interactive Lamp Web App

A beautiful, interactive hanging lamp web application built with FastAPI and modern web technologies.

## ✨ Features

- **Interactive Lamp**: Pull the string to toggle the lamp on/off
- **Beautiful Animations**: Smooth transitions and realistic lighting effects
- **Responsive Design**: Works perfectly on desktop, tablet, and mobile
- **Modern UI**: Clean, minimalist design with dark theme
- **Docker Ready**: Production-ready containerization
- **Accessibility**: Full keyboard navigation and screen reader support

## 🏗️ Project Structure

```
lamp_web_app/
├── src/                    # Source code directory
│   ├── main.py            # FastAPI application entry point
│   ├── server.py          # Server configuration (if needed)
│   ├── requirements.txt   # Python dependencies
│   ├── static/            # Static assets
│   │   ├── style.css      # Application styles
│   │   └── script.js      # JavaScript functionality
│   └── templates/         # Jinja2 templates
│       └── index.html     # Main application template
├── Dockerfile             # Docker container definition
├── start.sh              # Development start script
└── README.md             # This file
```

## 🚀 Quick Start

### Local Development

1. **Install dependencies:**
   ```bash
   chmod +x start.sh
   ./start.sh
   ```

2. **Or manually:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r src/requirements.txt
   python src/main.py
   ```

## ☁️ Azure App Service Deployment

Deploy your lamp web app to Azure App Service using our automated deployment script that follows Azure best practices.

### 🚀 Quick Deployment (Recommended)

Use our robust deployment script that handles everything automatically:

```bash
# Make script executable and run
chmod +x deploy-to-azure.sh
./deploy-to-azure.sh
```

The script will:
- ✅ Validate prerequisites (Azure CLI, Docker)
- ✅ Prompt for configuration with sensible defaults
- ✅ Create all required Azure resources
- ✅ Build and push your Docker image
- ✅ Configure system-managed identity for secure ACR access
- ✅ Set up ACR webhook for continuous deployment
- ✅ Enable HTTPS-only and container logging
- ✅ Verify deployment and provide health checks
- ✅ Show cleanup commands and useful management tips

### Prerequisites

1. **Install Azure CLI:**
   ```bash
   # macOS (using Homebrew)
   brew install azure-cli
   
   # Or download from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
   ```

2. **Login to Azure:**
   ```bash
   az login
   ```

3. **Ensure Docker is running:**
   - Install and start Docker Desktop

### 🔧 Manual Deployment (Advanced Users)

If you prefer manual control, here are the individual steps:

### Step 1: Create Azure Resources

```bash
# Set variables (customize these values)
RESOURCE_GROUP="lamp-app-rg"
APP_NAME="lamp-web-app-$(date +%s)"  # Unique name with timestamp
LOCATION="eastus2"  # Choose a region close to you
ACR_NAME="lampappregistry$(date +%s)"  # Must be globally unique

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry (Basic tier, NO admin user for security)
az acr create --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled false

# Create App Service Plan (Free tier)
az appservice plan create \
  --name "${APP_NAME}-plan" \
  --resource-group $RESOURCE_GROUP \
  --sku F1 \
  --is-linux

# Create Web App
az webapp create \
  --resource-group $RESOURCE_GROUP \
  --plan "${APP_NAME}-plan" \
  --name $APP_NAME \
  --deployment-container-image-name ${ACR_NAME}.azurecr.io/lamp-app:latest
```

### Step 2: Configure System-Managed Identity

```bash
# Enable system-managed identity for the Web App
PRINCIPAL_ID=$(az webapp identity assign \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --query principalId \
  --output tsv)

# Assign AcrPull role to the system-managed identity for secure ACR access
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --scope $(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id --output tsv) \
  --role AcrPull
```

### Step 3: Build and Push Docker Image

```bash
# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)

# Login to ACR using your Azure credentials (no admin credentials needed)
az acr login --name $ACR_NAME

# Build and tag the image
docker build -t $ACR_LOGIN_SERVER/lamp-app:latest .

# Push image to ACR (using your authenticated session)
docker push $ACR_LOGIN_SERVER/lamp-app:latest
```

### Step 4: Configure Web App with System-Managed Identity

```bash
# Configure the web app to use system-managed identity for ACR authentication
az webapp config container set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --docker-custom-image-name $ACR_LOGIN_SERVER/lamp-app:latest \
  --docker-registry-server-url https://$ACR_LOGIN_SERVER

# Configure app settings
az webapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --settings PORT=8000 PYTHONPATH=/app/src

# Enable HTTPS only for security
az webapp update \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --https-only true

# Enable container logging
az webapp log config \
  --resource-group $RESOURCE_GROUP \
  --name $APP_NAME \
  --docker-container-logging filesystem
```

### Step 5: Access Your App

```bash
# Get the actual URL of your deployed app
az webapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query defaultHostName --output tsv

# Check deployment status
az webapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query state --output tsv

# View logs (if needed for troubleshooting)
az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP
```

### 🔄 Update Deployment

To update your app with new changes:

```bash
# Using the update script (recommended - auto-discovers resources)
./update-app.sh
# ✨ Now with automatic webhook deployment! Just push and wait.

# Or specify resources explicitly
./update-app.sh RESOURCE_GROUP APP_NAME ACR_NAME

# Or using the full deployment script
./deploy-to-azure.sh

# Or manually rebuild and push updated image (if webhook is set up)
docker build -t $ACR_LOGIN_SERVER/lamp-app:latest .
docker push $ACR_LOGIN_SERVER/lamp-app:latest
# 🎯 Webhook automatically triggers App Service update - no restart needed!

# Manual restart (only needed if no webhook)
az webapp restart --name $APP_NAME --resource-group $RESOURCE_GROUP
```

### 🤖 Continuous Deployment with ACR Webhooks

The deployment script automatically sets up ACR webhooks for continuous deployment:

- **Automatic Updates**: Push to ACR → Webhook triggers → App Service pulls new image
- **No Manual Intervention**: No need to restart the app service manually
- **Real-time Deployment**: Changes deploy within 2-3 minutes of pushing
- **Webhook Management**: 
  ```bash
  # List webhooks
  az acr webhook list --registry ACR_NAME --output table
  
  # View webhook events
  az acr webhook list-events --registry ACR_NAME --name APP_NAME-webhook
  
  # Test webhook
  az acr webhook ping --registry ACR_NAME --name APP_NAME-webhook
  ```

### 🧹 Cleanup Resources

When you're done testing, clean up to avoid charges:

```bash
# Delete the entire resource group (removes all resources)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### 💡 Azure Free Tier Limitations

- **App Service Plan F1**: 1 GB RAM, 1 GB storage, 60 CPU minutes/day
- **Container Registry Basic**: 10 GB storage, unlimited pulls
- **Resource Group**: No cost, but monitor overall Azure free tier limits

### 🔒 Security Best Practices Implemented

- **✅ System-Managed Identity**: Web app uses system-managed identity for secure ACR access (no user-assigned identity needed)
- **✅ No Admin Credentials**: ACR admin user disabled, uses RBAC instead
- **✅ Least Privilege**: System-managed identity has only AcrPull permissions (minimum required)
- **✅ HTTPS Only**: All traffic forced to HTTPS for encryption in transit
- **✅ No Hardcoded Secrets**: No usernames/passwords stored in app configuration
- **✅ Resource Scoping**: Identity scoped to specific ACR resource
- **✅ RBAC Authentication**: Role-based access control instead of shared credentials
- **✅ Container Registry Privacy**: Private registry with identity-based authentication
- **✅ Automated Deployment**: Robust script with error handling and validation
- **✅ Webhook Security**: Secure webhook URLs with proper authentication

## 🐳 Docker Commands

### Development
```bash
# Build the image
docker build -t lamp-app .

# Run the container
docker run -p 8000:8000 lamp-app

# Run with environment variables
docker run -p 8000:8000 -e PORT=8000 lamp-app
```

### Production
```bash
# Build for production
docker build -t lamp-app:prod .

# Run in production mode
docker run -d --name lamp-app -p 8000:8000 --restart unless-stopped lamp-app:prod
```

## 🛠️ Docker Best Practices Implemented

- **Multi-stage builds**: Optimized image size
- **Non-root user**: Enhanced security
- **Health checks**: Container health monitoring
- **Environment variables**: Configurable runtime
- **Slim base image**: Python 3.13-slim for smaller footprint
- **Layer caching**: Efficient builds with proper layer ordering
- **Security**: No new privileges, resource limits

## 🔧 Configuration

### Environment Variables

- `PORT`: Application port (default: 8000)
- `PYTHONPATH`: Python path (set to `/app/src` in Docker)

### Health Check

The application includes a health check endpoint at `/health`

## 🎨 Technologies Used

- **Backend**: FastAPI (Python 3.13)
- **Frontend**: Vanilla JavaScript, CSS3, HTML5
- **Animations**: Anime.js library
- **Containerization**: Docker
- **Cloud Platform**: Azure App Service
- **Container Registry**: Azure Container Registry
- **Web Server**: Uvicorn (ASGI server)

## 📱 Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## 🔗 API Endpoints

- `GET /`: Main application interface
- `GET /health`: Health check endpoint
- `GET /static/*`: Static file serving

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with Docker
5. Submit a pull request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
