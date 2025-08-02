#!/usr/bin/env python3
"""
Development server script for the Lamp Web App
Run this script to start the development server with auto-reload
"""

import subprocess
import sys
import os

def install_dependencies():
    """Install required dependencies if they're not available."""
    try:
        import fastapi
        import uvicorn
        import jinja2
        print("✅ All dependencies are installed!")
        return True
    except ImportError as e:
        print(f"❌ Missing dependency: {e}")
        print("🔧 Please run the following commands:")
        print("   python3 -m venv venv")
        print("   source venv/bin/activate")
        print("   pip install -r requirements.txt")
        print("   source venv/bin/activate && python3 server.py")
        print("")
        print("Or run with virtual environment activated:")
        print("   source venv/bin/activate && ./start.sh")
        return False

def main():
    """Main development server startup."""
    print("🪔 Starting Lamp Web App Development Server...")
    print("=" * 50)
    
    # Check if we're in the right directory
    if not os.path.exists("main.py"):
        print("❌ main.py not found. Please run this script from the lamp_web_app directory.")
        return
    
    # Install dependencies if needed
    if not install_dependencies():
        return
    
    print("\n🚀 Starting server...")
    print("📍 URL: http://127.0.0.1:8000")
    print("📖 API Docs: http://127.0.0.1:8000/docs")
    print("💡 Press Ctrl+C to stop the server")
    print("=" * 50)
    
    try:
        # Start the development server
        subprocess.run([
            sys.executable, "-m", "uvicorn", 
            "main:app", 
            "--reload", 
            "--host", "0.0.0.0", 
            "--port", "8000"
        ])
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped. Thanks for using Lamp Web App!")
    except Exception as e:
        print(f"\n❌ Error starting server: {e}")
        print("Try running manually: uvicorn main:app --reload")

if __name__ == "__main__":
    main()
