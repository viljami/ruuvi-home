#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

echo "Quick fix for Ruuvi Home password URL encoding issue"
echo "===================================================="

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# Backup current .env
cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
echo "✓ Backed up .env file"

# Fix DATABASE_URL by URL-encoding special characters
sed -i 's|DATABASE_URL=postgresql://ruuvi:8r0kauU+c13hMGnN6DO3AI9O4yP0HSeds6ampbvdKco=@timescaledb:5432/ruuvi_home|DATABASE_URL=postgresql://ruuvi:8r0kauU%2Bc13hMGnN6DO3AI9O4yP0HSeds6ampbvdKco%3D@timescaledb:5432/ruuvi_home|' "$ENV_FILE"

# Fix AUTH_DATABASE_URL by URL-encoding special characters
sed -i 's|AUTH_DATABASE_URL=postgresql://auth_user:ZzvFn9T3nADjnw7Alpb/Is8m1ZbqQaqoiynlTR9UwtM=@auth-db:5432/auth|AUTH_DATABASE_URL=postgresql://auth_user:ZzvFn9T3nADjnw7Alpb%2FIs8m1ZbqQaqoiynlTR9UwtM%3D@auth-db:5432/auth|' "$ENV_FILE"

echo "✓ Fixed URL encoding in DATABASE_URL and AUTH_DATABASE_URL"

# Restart services
cd "$PROJECT_ROOT"
echo "Restarting services..."

if command -v docker-compose >/dev/null 2>&1; then
    docker-compose down
    docker-compose up -d
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose down
    docker compose up -d
else
    echo "ERROR: Neither docker-compose nor docker compose found!"
    exit 1
fi

echo "✓ Services restarted"

# Wait and test
echo "Waiting for API server to start..."
sleep 10

for i in {1..30}; do
    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo "✅ SUCCESS: API server is responding!"
        echo ""
        echo "Your Ruuvi Home is now working properly."
        echo "Access the dashboard at: http://$(hostname -I | awk '{print $1}'):3000"
        exit 0
    fi
    echo "Waiting... (attempt $i/30)"
    sleep 2
done

echo "❌ API server still not responding. Check logs:"
echo "docker compose logs api-server"
