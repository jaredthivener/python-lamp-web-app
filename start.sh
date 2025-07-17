#!/bin/bash
# Complete start script for the Enhanced Lamp Web App

echo "🪔 Enhanced Lamp Web App"
echo "=============================="
echo ""
echo "🎨 Features included:"
echo "   ✨ Beautiful 3D lamp design with realistic shadows"
echo "   🌙 Smooth light transitions and animations"
echo "   📱 Mobile-responsive with touch support"
echo "   🐳 Docker-ready with production optimizations"
echo "   ⌨️  Keyboard shortcuts (L for lamp toggle)"
echo "   🎭 Particle animations and visual effects"
echo "   ♿ Accessibility improvements"
echo "   💾 State persistence (remembers preferences)"
echo "   🔧 Error handling and graceful fallbacks"
echo ""

# Check if uv is available
if ! command -v uv &> /dev/null; then
    echo "❌ uv not found. Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null || true
    if ! command -v uv &> /dev/null; then
        echo "❌ uv installation failed. Please install manually: https://docs.astral.sh/uv/getting-started/installation/"
        exit 1
    fi
fi
echo "✅ uv is available"

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 not found. Please install Python 3.12+"
    exit 1
fi

# Check Python version
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
REQUIRED_VERSION="3.12"
if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 12) else 1)" 2>/dev/null; then
    echo "❌ Python $PYTHON_VERSION found, but this project requires Python $REQUIRED_VERSION or higher"
    echo "   Please upgrade your Python installation"
    exit 1
fi
echo "✅ Python $PYTHON_VERSION is available"

# Check if port 8000 is already in use
if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port 8000 is already in use. Stopping existing server..."
    pkill -f "uvicorn.*8000" 2>/dev/null || true
    pkill -f "python.*server" 2>/dev/null || true
    sleep 2
fi

# Check if virtual environment exists and sync dependencies
if [ ! -d ".venv" ]; then
    echo "🔧 Creating virtual environment with uv..."
    uv venv .venv
    echo "✅ Virtual environment created!"
fi

# Activate virtual environment
echo "🔄 Activating virtual environment..."
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
else
    echo "❌ .venv/bin/activate not found. Virtual environment activation failed."
    exit 1
fi

# Install dependencies
echo "📦 Installing dependencies with uv..."
if [ -f "pyproject.toml" ]; then
    # Try to install in editable mode first, fallback to requirements.txt
    if ! uv pip install -e .; then
        echo "⚠️  Editable install failed, falling back to requirements.txt..."
        uv pip install -r src/requirements.txt
    fi
else
    uv pip install -r src/requirements.txt
fi
echo "✅ Dependencies installed!"

echo ""
echo "🚀 Starting the development server..."
echo "   📍 Main App: http://127.0.0.1:8000"
echo "   📖 API Docs: http://127.0.0.1:8000/docs"
echo "   🩺 Health Check: http://127.0.0.1:8000/health"
echo ""
echo "🎮 How to use:"
echo "   • Click the lamp or press 'L' to toggle the light"
echo "   • Pull the string for interactive lamp control"
echo "   • Tab to navigate with keyboard"
echo "   • Enjoy the smooth animations and particle effects!"
echo ""
echo "💡 Press Ctrl+C to stop the server"
echo "=============================="

# Start the server
python3 src/main.py
