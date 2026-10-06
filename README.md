# 🪔 Interactive Lamp Web App

[![Tests](https://github.com/jaredthivener/python-lamp-web-app/actions/workflows/ci.yml/badge.svg)](https://github.com/jaredthivener/python-lamp-web-app/actions/workflows/ci.yml)
[![Github CodeQL](https://github.com/jaredthivener/python-lamp-web-app/actions/workflows/security-native.yml/badge.svg)](https://github.com/jaredthivener/python-lamp-web-app/actions/workflows/security-native.yml)

> **Modern containerized Python web application with production-ready Azure infrastructure**

A beautiful, interactive hanging lamp web application built with FastAPI, featuring modular Bicep infrastructure and modern DevOps practices for seamless Azure deployment.

---

## 📋 Table of Contents

- [✨ Features](#-features)
- [🏗️ Architecture](#️-architecture)
- [🚀 Quick Start](#-quick-start)
- [☁️ Azure Deployment](#️-azure-deployment)
- [🔧 Development](#-development)
- [🐳 Docker](#-docker)
- [🔒 Security](#-security)
- [📊 Monitoring](#-monitoring)
- [🤝 Contributing](#-contributing)

---

## ✨ Features

### 🎨 **Interactive Experience**

- **One Shared Lamp**: Everyone with the page open sees the same lamp. Pull the cord and it switches for all of them, live, over Server-Sent Events
- **Light You Can Read By**: The page is a wall and the lamp really lights it. A WebGL shader computes the falloff, the shade's cutoff, dust in the beam, and the shadows the stat cards cast
- **Writing That Leaves**: A few seconds after the page opens, the words on the wall turn to ash and a gust carries them off
- **Real Physics**: The lamp hangs from a cord and rocks where the cord meets it; the ball chain is a rope. Pull the chain and the shade dips toward your hand, then sways back to rest
- **No Frontend Dependencies**: No framework, no CDN, no build step. A few ES modules, a stylesheet and two short recordings
- **Responsive Design**: Optimized for desktop, tablet, and mobile devices
- **Accessibility**: The cord is a real button (Tab, Enter, Space, or the `L` key); reduced-motion and forced-colors are respected, with a plain fallback where WebGL is unavailable

### 🏗️ **Architecture**

- **Modular Bicep Infrastructure**: Maintainable, reusable Azure infrastructure as code
- **Container-First**: Optimized Docker containers with multi-stage builds
- **Auto-Scaling**: Azure App Service with configurable scaling policies
- **Zero-Downtime Deployment**: ACR webhooks for continuous deployment

### 🔒 **Enterprise Security**

- **Managed Identity**: Secure Azure resource authentication without credentials
- **HTTPS-Only**: TLS encryption enforced across all endpoints
- **Role-Based Access**: Least privilege ACR access with AcrPull role
- **Secret-Free**: No hardcoded credentials or connection strings

---

## 🏗️ Architecture

```mermaid
graph TB
    subgraph "Development"
        DEV[Developer] -->|git push| GIT[Git Repository]
        GIT -->|docker build| LOCAL[Local Testing]
    end

    subgraph "Azure Cloud"
        subgraph "Infrastructure (Bicep)"
            RG[Resource Group]
            MI[Managed Identity]
            ACR[Container Registry]
            ASP[App Service Plan]
            APP[App Service]
            AI[Application Insights]
            LA[Log Analytics]
        end

        subgraph "Deployment Pipeline"
            BUILD[ACR Build] --> WEBHOOK[ACR Webhook]
            WEBHOOK --> DEPLOY[Auto Deploy]
        end
    end

    subgraph "Monitoring"
        LOGS[Centralized Logging]
        METRICS[Performance Metrics]
        ALERTS[Smart Alerts]
    end

    DEV -->|az acr build| BUILD
    APP -->|Logs & Metrics| LOGS
    APP -->|Telemetry| METRICS
    MI -->|AcrPull| ACR
    APP -->|Uses| MI
```

### 🧩 **Modular Infrastructure**

| Component                 | Purpose                    | Technology                           |
| ------------------------- | -------------------------- | ------------------------------------ |
| **🔍 Monitoring**         | Observability & logging    | Log Analytics + Application Insights |
| **🔐 Identity**           | Secure authentication      | System-assigned Managed Identity     |
| **📦 Container Platform** | Image storage & management | Azure Container Registry             |
| **🌐 Compute**            | Application hosting        | App Service with Linux containers    |
| **🔗 Integration**        | CI/CD automation           | ACR webhooks + role assignments      |

---

## 🚀 Quick Start

### Prerequisites

```bash
# Required tools
az --version      # Azure CLI
docker --version  # Docker
bicep --version   # Bicep CLI (optional for infrastructure)
```

### 1️⃣ **Clone & Setup**

```bash
git clone <repository-url>
cd python-lamp-web-app

# Make scripts executable
chmod +x start.sh
```

### 2️⃣ **Local Development**

```bash
# Quick start with auto-setup
./start.sh

# Or run it directly (uv creates the environment from pyproject.toml)
uv run python src/main.py

# Run the tests
uv run pytest   # API and storage
npm test        # lamp physics (plain Node, nothing to install)
```

With no `POSTGRES_CONNECTION_STRING` or `KEY_VAULT_URI` set, the lamp is kept in a local SQLite file, so there is nothing else to install.

### 3️⃣ **Deploy to Azure**

```bash
# Login to Azure
az login

# Deploy infrastructure + application (recommended)
azd up
```

**🎉 That's it! Your app will be live in minutes with full monitoring and continuous deployment!**

---

## ☁️ Azure Deployment

### 🎯 **Modern Infrastructure (Recommended)**

Deploy using **modular Bicep templates** for production-ready infrastructure:

```bash
# Navigate to infrastructure directory
cd infra

# Preview deployment
az deployment sub create \
  --location eastus2 \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --what-if

# Deploy infrastructure
az deployment sub create \
  --location eastus2 \
  --template-file main.bicep \
  --parameters main.bicepparam

# Build and deploy application
az acr build --registry <acr-name> --image lamp-app:latest .
```

### 📁 **Infrastructure Structure**

```
infra/
├── 📄 main.bicep                    # 🎯 Main orchestration template
├── ⚙️ main.bicepparam              # 🔧 Modern parameter file
├── 🔧 bicepconfig.json             # 📋 Bicep linting configuration
└── 📁 modules/
    ├── 🔍 monitoring.bicep         # Log Analytics + App Insights
    ├── 🔐 managed-identity.bicep   # System-assigned identity
    ├── 📦 acr.bicep               # Container registry
    ├── 🌐 appservice.bicep        # App Service plan + web app
    └── 🔗 acr-integration.bicep   # Role assignment + webhook
```

### 🔧 **Environment Configuration**

Customize deployment via `infra/main.bicepparam`:

```bicep
// Environment Configuration
param environmentName = 'dev'           // dev, staging, prod
param location = 'eastus2'              // Azure region
param resourceGroupName = 'rg-lamp-web-app-dev'

// App Service Configuration
param appServicePlanSku = 'B1'          // B1, S1, P1v3, etc.
param appPort = '8000'                  // Application port

// Container Registry
param containerRegistrySku = 'Basic'    // Basic, Standard, Premium
```

### 🚀 **Quick Deployment (Shell Script)**

For rapid deployment with automated best practices:

```bash
# Automated deployment with modern best practices
./deploy-to-azure.sh

# Features:
# ✅ Infrastructure validation
# ✅ Resource provisioning
# ✅ Docker build & push
# ✅ System-managed identity configuration
# ✅ Webhook setup for continuous deployment
# ✅ Health verification
```

### 🔄 **Update Deployment**

```bash
# Rebuild and push (webhook automatically deploys)
docker build -t <acr-name>.azurecr.io/lamp-app:latest .
docker push <acr-name>.azurecr.io/lamp-app:latest

# Or use ACR build
az acr build --registry <acr-name> --image lamp-app:latest .
```

---

## 🔧 Development

### 📁 **Project Structure**

```
python-lamp-web-app/
├── 📁 src/                      # 🐍  Python application
│   ├── main.py                  # 🚀  FastAPI app: API, live event stream, static files
│   ├── store.py                 # 🗄️  Lamp state and activity log (SQLAlchemy)
│   └── 📁 static/               # 🎨  Frontend (served as-is, no build step)
│       ├── index.html           # 🏠  The page
│       ├── ash.js               # 🌬️  The words on the wall blowing away as ash
│       ├── style.css            # 💅  Layout and type
│       ├── lamp.js              # ⚡  Input, server sync, frame loop
│       ├── physics.js           # 🪀  How the lamp and chain move (tuning constants at the top)
│       ├── scene.js             # 💡  WebGL shader that draws the lamp and its light
│       ├── sound.js             # 🔔  Plays the pull chain
│       └── chain-*.wav          # 🎙️  A real pull chain, recorded (see Credits)
├── 📁 tests/                    # 🧪  pytest (SQLite locally, plus Postgres in CI) and Node physics tests
├── pyproject.toml               # 📦  The only dependency list
├── 📁 infra/                    # ☁️  Azure infrastructure
│   ├── main.bicep               # 🎯  Main Bicep template
│   ├── main.bicepparam          # 🔧  Parameters
│   └── 📁 modules/              # 🧩  Modular components
├── 🐳 Dockerfile                # 📦  Container definition
├── 🚀 start.sh                  # 🛠️  Development script
├── ☁️ deploy-to-azure.sh        # ⚡  Azure deployment
└── 📖 README.md                 # 📚  This documentation
```

### 🔌 **API**

| Endpoint                   | Purpose                                                                 |
| -------------------------- | ----------------------------------------------------------------------- |
| `GET /api/v1/lamp/status`  | Lamp state plus counters (today, lifetime, visitors, people watching)   |
| `POST /api/v1/lamp/toggle` | Pull the cord. Atomic in the database; at most two per second, lamp-wide |
| `GET /api/v1/lamp/events`  | Server-Sent Events: the same snapshot, pushed whenever it changes       |
| `GET /health`              | Liveness for Docker and App Service; reports a lost database as degraded |

State lives in Postgres (`lamp_status`, `lamp_activities`). If the database goes away the page keeps showing the last known state and pulls fail loudly rather than being silently dropped; it reconnects on its own.

### 🛠️ **Development Workflow**

1. **🧪 Local Testing**

   ```bash
   ./start.sh                    # Start development server
   open http://localhost:8000    # Test functionality
   ```

2. **🏗️ Infrastructure Validation**

   ```bash
   cd infra
   bicep build main.bicep        # Validate Bicep syntax
   az deployment sub validate --template-file main.bicep --parameters main.bicepparam
   ```

3. **🐳 Container Testing**

   ```bash
   docker build -t lamp-app .
   docker run -p 8000:8000 lamp-app
   ```

4. **☁️ Deploy Changes**
   ```bash
   az acr build --registry <acr-name> --image lamp-app:latest .
   # 🎯 Webhook automatically deploys to App Service!
   ```

---

## 🐳 Docker

### 🎯 **Production Optimizations**

Our Docker setup includes modern best practices:

```dockerfile
# Multi-stage build for optimal size
FROM python:3.13.5-slim as builder
# ... build dependencies

FROM python:3.13.5-slim as runtime
# ... minimal runtime image
```

**Features:**

- ✅ **Multi-stage builds** for smaller images (~150MB)
- ✅ **Non-root user** for enhanced security
- ✅ **Health checks** for container monitoring
- ✅ **Layer caching** for faster builds
- ✅ **Security scanning** compatible

### 📦 **Docker Commands**

```bash
# Development
docker build -t lamp-app .
docker run -p 8000:8000 lamp-app

# Production
docker build -t lamp-app:prod .
docker run -d --name lamp-app \
  -p 8000:8000 \
  --restart unless-stopped \
  lamp-app:prod

# Health check
curl http://localhost:8000/health
```

---

## 🔒 Security

### 🛡️ **Enterprise Security Features**

| Security Layer | Implementation                    | Benefit                  |
| -------------- | --------------------------------- | ------------------------ |
| **Identity**   | System-assigned Managed Identity  | No credential management |
| **Access**     | Azure RBAC with AcrPull role      | Least privilege access   |
| **Transport**  | HTTPS-only enforcement            | Encrypted communication  |
| **Storage**    | Private container registry        | Secure image storage     |
| **Secrets**    | Azure Key Vault integration ready | No hardcoded secrets     |

### 🔐 **Security Validations**

```bash
# Check security configuration
az webapp show --name <app-name> --resource-group <rg> \
  --query "{httpsOnly:httpsOnly, identity:identity.type}"

# Verify role assignments
az role assignment list --assignee <principal-id> \
  --query "[].{Role:roleDefinitionName, Scope:scope}"
```

### ✅ **Security Best Practices Implemented**

- **System-Managed Identity**: Secure ACR access without stored credentials
- **No Admin Credentials**: ACR admin user disabled, uses RBAC instead
- **Least Privilege**: Only AcrPull permissions (minimum required)
- **HTTPS Only**: All traffic encrypted in transit
- **Resource Scoping**: Identity scoped to specific ACR resource
- **Automated Security**: Robust deployment with validation

---

## 📊 Monitoring

### 📈 **Built-in Observability**

**Real-time Monitoring:**

- 🔍 **Application Insights** - Performance, errors, dependencies
- 📋 **Log Analytics** - Centralized logging and queries
- 🚨 **Smart Alerts** - Proactive issue detection
- 📊 **Custom Dashboards** - Business metrics visualization

**Key Metrics Tracked:**

- Application response times
- Error rates and exceptions
- Container resource utilization
- User interaction patterns

### 🔍 **Monitoring Access**

```bash
# View application logs
az webapp log tail --name <app-name> --resource-group <rg>

# Application Insights metrics
az monitor app-insights component show \
  --app <ai-name> --resource-group <rg>

# Custom queries in Log Analytics
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "requests | summarize count() by bin(timestamp, 1h)"
```

---

## 🤝 Contributing

### 🔄 **Development Workflow**

1. **🍴 Fork & Clone**

   ```bash
   git clone <your-fork>
   cd python-lamp-web-app
   ```

2. **🧪 Test Locally**

   ```bash
   ./start.sh
   # Test your changes
   ```

3. **🏗️ Validate Infrastructure**

   ```bash
   cd infra
   bicep build main.bicep
   az deployment sub validate --template-file main.bicep --parameters main.bicepparam
   ```

4. **🐳 Test Container**

   ```bash
   docker build -t lamp-app-dev .
   docker run -p 8000:8000 lamp-app-dev
   ```

5. **📤 Submit PR**
   ```bash
   git push origin feature-branch
   # Create pull request
   ```

### 📋 **Contribution Guidelines**

- ✅ Follow Python PEP 8 style guidelines
- ✅ Update tests for new features
- ✅ Validate Bicep templates before submission
- ✅ Include documentation updates
- ✅ Test on multiple environments

---

## 🛠️ **Technologies**

### Backend Stack

- **🐍 FastAPI** - Modern Python web framework, with Server-Sent Events for live updates
- **🚀 Uvicorn** - ASGI server for production
- **🗄️ SQLAlchemy + PostgreSQL** - Lamp state and activity log
- **🐳 Docker** - Containerization
- **☁️ Azure App Service** - Cloud hosting

### Frontend Stack

- **🎨 Vanilla JavaScript** - ES modules, no dependencies, no build step
- **💡 WebGL 2** - One fragment shader for the lamp and its light
- **🎨 CSS3** - Modern styling
- **📱 Responsive Design** - Mobile-first approach

### Infrastructure

- **🏗️ Azure Bicep** - Infrastructure as Code
- **🔐 Managed Identity** - Secure authentication
- **📦 Azure Container Registry** - Private image registry
- **📊 Application Insights** - APM & monitoring

---

## 🎙️ Credits

The pull-chain sound is cut from ["Desk Lamp - Chain Pull (Fast)"](https://freesound.org/s/541762/) by PhillipArthurSimmons on Freesound, released into the public domain (CC0).

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

<div align="center">

**🎉 Built with ❤️ using modern Azure practices**

🚀 **Ready for Production** | 🔒 **Enterprise Secure** | 📊 **Fully Monitored**

</div>
