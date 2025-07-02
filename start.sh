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

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 not found. Please install Python 3.8+"
    exit 1
fi
echo "✅ Python3 is available"

# Check if port 8000 is already in use
if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port 8000 is already in use. Stopping existing server..."
    pkill -f "uvicorn.*8000" 2>/dev/null || true
    pkill -f "python.*server" 2>/dev/null || true
    sleep 2
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "🔧 Creating virtual environment..."
    python3 -m venv venv
    echo "✅ Virtual environment created!"
fi

# Activate virtual environment
echo "🔄 Activating virtual environment..."
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
else
    echo "❌ venv/bin/activate not found. Virtual environment activation failed."
    exit 1
fi

# Install dependencies if needed
if ! python3 -c "import fastapi, uvicorn, jinja2" 2>/dev/null; then
    echo "📦 Installing dependencies..."
    pip install -r src/requirements.txt
    echo "✅ Dependencies installed!"
fi

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
