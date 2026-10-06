#!/bin/bash

# Development database initialization script
# Run this script inside the dev container to set up the local PostgreSQL database

set -e

echo "🔧 Initializing development database..."

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
until pg_isready -h postgres -p 5432 -U postgres; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

echo "✅ PostgreSQL is ready!"

# Run the database initialization
echo "🗄️ Creating database tables..."
cd /workspaces/python-lamp-web-app/src
python -c "
import sys
sys.path.insert(0, '/workspaces/python-lamp-web-app/src')
from store import Store

try:
    Store().ping()
    print('✅ Database initialization completed successfully!')
except Exception as e:
    print(f'❌ Database initialization failed: {e}')
    sys.exit(1)
"

echo "🎉 Development environment is ready!"
echo "🚀 You can now start the application with: uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
