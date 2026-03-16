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

# Wait up to 60s for a container to be running and healthy (or have no healthcheck)
_wait_healthy() {
  local name="$1"
  local max_wait=60
  local elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    running=$(docker inspect --format='{{.State.Running}}' "$name" 2>/dev/null || echo "false")
    if [ "$running" != "true" ]; then
      echo "  ❌ $name is not running!"
      return 1
    fi
    status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$name" 2>/dev/null)
    if [ "$status" = "healthy" ] || [ "$status" = "no-healthcheck" ]; then
      echo "  ✅ $name ($status)"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  echo "  ⚠️  $name still '$status' after ${max_wait}s"
  return 1
}

echo "=== Homeserver Full Deploy ==="

echo "[1/3] Syncing all repos to origin/main..."
_sync .
_sync ../CNCSearch
_sync ../GarminBot
_sync ../HetznerCheck
_sync ../JMJ2027

echo "[2/3] Rebuilding and restarting all services..."
docker compose up -d --build

echo "[3/3] Waiting for containers to become healthy..."
all_ok=true
for svc in cncsearch cncsearch_caddy garminbot hetzner-monitor jmj2027; do
  _wait_healthy "$svc" || all_ok=false
done

echo ""
docker compose ps

if [ "$all_ok" = "true" ]; then
  echo ""
  echo "✅ Deploy concluído — todos os serviços saudáveis."
else
  echo ""
  echo "⚠️  Deploy com avisos — verifica os logs abaixo."
  docker compose logs --tail=30
  exit 1
fi
