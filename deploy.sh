#!/usr/bin/env bash
#
# deploy.sh - Pull ALL repos, rebuild and restart ALL services
#
# For updating a single service, use that service's own deploy.sh instead.
#
# Usage: bash deploy.sh

set -euo pipefail
cd "$(dirname "$0")"

# Hard-reset a repo to match the remote (no local changes should live on the server)
_sync() {
  local dir="$1"
  echo "  Syncing $dir..."
  git -C "$dir" fetch origin
  git -C "$dir" reset --hard origin/main
}

echo "=== Homeserver Full Deploy ==="

echo "[1/3] Syncing all repos to origin/main..."
_sync ../CNCSearch
_sync ../GarminBot
_sync ../HetznerCheck

echo "[2/3] Rebuilding and restarting all services..."
docker compose up -d --build

echo "[3/3] Status:"
docker compose ps

echo ""
echo "Logs (Ctrl+C to stop watching)..."
docker compose logs -f --tail=20
