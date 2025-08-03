# Development Container Setup

This project includes a complete development container setup for Visual Studio Code that provides a consistent development environment with all necessary tools and dependencies.

## Features

- **Python 3.13** with FastAPI and all project dependencies
- **uv package manager** for faster Python package installation and management
- **PostgreSQL 15** database for local development
- **Azure CLI** for Azure resource management
- **Docker-in-Docker** for container operations
- **Pre-configured VS Code extensions** for Python, Azure, and web development
- **Database initialization scripts** for quick setup
- **Development tools**: Black, Flake8, Pytest, MyPy, and more

## Quick Start

1. **Prerequisites**:

   - [Visual Studio Code](https://code.visualstudio.com/)
   - [Docker Desktop](https://www.docker.com/products/docker-desktop)
   - [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

2. **Open in Dev Container**:

   - Open this project in VS Code
   - Click "Reopen in Container" when prompted, or
   - Use Command Palette: `Dev Containers: Reopen in Container`

3. **Initialize the Database**:

   ```bash
   # Run the initialization script
   ./.devcontainer/init-dev-db.sh
   ```

4. **Start the Application**:

   ```bash
   # Start the FastAPI development server
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

   Or use VS Code tasks:

   - `Ctrl+Shift+P` → `Tasks: Run Task` → `Start FastAPI Development Server`

## Available VS Code Tasks

- **Start FastAPI Development Server**: Runs the application with hot reload
- **Initialize Development Database**: Sets up the PostgreSQL database
- **Run Tests**: Executes the test suite with pytest
- **Format Code with Black**: Formats Python code
- **Lint with Flake8**: Checks code quality
- **Install Dependencies with uv**: Installs project dependencies using uv
- **Install Dev Dependencies with uv**: Installs development dependencies using uv
- **Deploy to Azure**: Deploys to Azure using `azd up`

## Package Management with uv

This dev container uses [uv](https://docs.astral.sh/uv/) for faster Python package management:

```bash
# Install project dependencies
uv pip install -r requirements.txt

# Install a new package
uv pip install package-name

# Install development dependencies
uv pip install pytest black flake8 mypy

# Sync dependencies (if using pyproject.toml)
uv pip sync requirements.txt
```

uv is significantly faster than pip and provides better dependency resolution.

## Available Launch Configurations

- **FastAPI: Run Development Server**: Debug the main application
- **FastAPI: Run with Uvicorn**: Debug with Uvicorn server
- **Initialize Database**: Debug the database initialization script

## Environment Variables

The dev container sets up these environment variables:

- `PYTHONPATH=/workspaces/python-lamp-web-app/src`
- `ENVIRONMENT=development`
- `POSTGRES_CONNECTION_STRING=postgresql://postgres:password@postgres:5432/lamp_db`

## Services

### Application Service (app)

- **Port**: 8000 (forwarded to host)
- **Environment**: Development with hot reload
- **Volume**: Project files mounted for development

### PostgreSQL Service (postgres)

- **Port**: 5432 (accessible from host)
- **Database**: `lamp_db`
- **Username**: `postgres`
- **Password**: `password`
- **Data**: Persisted in Docker volume

## Development Workflow

1. **Make code changes** - Files are automatically synced
2. **Database changes** - Use the initialization script or manual SQL
3. **Run tests** - Use the VS Code task or `pytest` command
4. **Format code** - Use the Black formatter task or save with auto-format
5. **Deploy** - Use the Azure deployment task when ready

## Troubleshooting

### Container won't start

- Ensure Docker Desktop is running
- Try rebuilding: `Dev Containers: Rebuild Container`

### Database connection issues

- Wait for PostgreSQL to fully start (check logs)
- Run the initialization script: `./.devcontainer/init-dev-db.sh`

### Port conflicts

- Check if port 8000 or 5432 are already in use
- Modify ports in `docker-compose.yml` if needed

### Python path issues

- Verify `PYTHONPATH` is set correctly
- Check VS Code settings for Python interpreter path

## Azure Integration

When ready to work with Azure resources:

1. **Login to Azure**:

   ```bash
   az login
   azd auth login
   ```

2. **Set environment variables** for Azure:

   - `KEY_VAULT_URI=https://your-keyvault.vault.azure.net/`
   - `AZURE_CLIENT_ID=your-managed-identity-client-id`

3. **Deploy to Azure**:
   ```bash
   azd up
   ```

## Files Structure

```
.devcontainer/
├── devcontainer.json       # Dev container configuration
├── Dockerfile             # Custom container definition
├── docker-compose.yml     # Multi-service setup
├── init-dev-db.sh         # Database initialization script
└── .env.template          # Environment variables template

.vscode/
├── launch.json            # Debug configurations
├── settings.json          # VS Code settings
└── tasks.json             # Development tasks
```

This setup provides a complete, isolated development environment that matches the production deployment architecture while being optimized for local development and debugging.
