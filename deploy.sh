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
  local branch="${2:-main}"
  echo "  Syncing $dir..."
  git -C "$dir" fetch origin
  git -C "$dir" reset --hard "origin/$branch"
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
_sync ../GitlabMCPServer
_sync ../GarminBot
_sync ../HetznerCheck
_sync ../JMJ2027
_sync ../liturgia-das-horas
_sync ../PTSquawk master
_sync ../PTEvents master

echo "[2/3] Rebuilding and restarting all services..."
docker compose up -d --build

# The Caddyfile is a single-file bind-mount. `git reset --hard` rewrites it with
# a new inode, but a running container stays bound to the OLD inode — so neither
# `up -d` (spec unchanged → not recreated) nor `caddy reload` (reads the stale
# in-container file) picks up Caddyfile changes. Force-recreate Caddy so it
# remounts the current file.
echo "  Recreating Caddy to pick up Caddyfile changes..."
docker compose up -d --force-recreate caddy \
  || echo "  ⚠️  Caddy recreate failed — check Caddyfile syntax"

echo "[3/4] Waiting for containers to become healthy..."
all_ok=true
for svc in cncsearch cncsearch_caddy garminbot hetzner-monitor jmj2027 liturgia-bot ptsquawk ptevents phoenix; do
  _wait_healthy "$svc" || all_ok=false
done

# Every `--build` leaves cache layers behind; across ~10 services this silently
# ate 8.7GB over 8 weeks with zero manual pruning. Keep a week of cache for fast
# incremental rebuilds, drop anything older.
echo "[4/4] Pruning build cache older than 7 days..."
docker builder prune -af --filter "until=168h" || echo "  ⚠️  Build cache prune failed"

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
