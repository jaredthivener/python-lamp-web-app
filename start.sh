#!/bin/bash
# Start script for the Lamp Web App (local development)

echo "🪔 Lamp Web App"
echo "=============================="

# Check if uv is available
if ! command -v uv &> /dev/null; then
    echo "❌ uv not found. Install it first: https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
fi

# Check if the port is already in use
if lsof -Pi :${PORT:-8000} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "❌ Port ${PORT:-8000} is already in use. Stop whatever is listening there, or pick another: PORT=8001 ./start.sh"
    exit 1
fi

echo ""
echo "   📍 Main App: http://127.0.0.1:${PORT:-8000}"
echo "   📖 API Docs: http://127.0.0.1:${PORT:-8000}/docs"
echo "   🩺 Health Check: http://127.0.0.1:${PORT:-8000}/health"
echo ""
echo "🎮 How to use:"
echo "   • Drag the chain down, or tap its knob, to switch the lamp"
echo "   • Press 'L', or Tab to the cord and press Enter"
echo "   • Open a second window: both show the same lamp, live"
if [ -z "$POSTGRES_CONNECTION_STRING" ] && [ -z "$KEY_VAULT_URI" ]; then
    echo ""
    echo "ℹ️  No POSTGRES_CONNECTION_STRING or KEY_VAULT_URI detected."
    echo "   The lamp will be kept in a local SQLite file instead."
fi
echo ""
echo "💡 Press Ctrl+C to stop the server"
echo "=============================="

# uv creates the virtual environment and installs pyproject.toml's dependencies as needed
exec uv run python src/main.py
