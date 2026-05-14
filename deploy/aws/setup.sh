#!/usr/bin/env bash
# Bootstrap script for a fresh AWS Lightsail Ubuntu 22.04 instance.
# Idempotent: re-running is safe.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
APP_DIR="${APP_DIR:-/opt/shopify_erp_2}"

echo "[setup] region=${REGION} app_dir=${APP_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[setup] installing Docker"
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" || true
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "[setup] installing docker compose plugin"
  sudo apt-get update
  sudo apt-get install -y docker-compose-plugin
fi

sudo mkdir -p "$APP_DIR"
sudo chown "$USER:$USER" "$APP_DIR"
cd "$APP_DIR"

if [ ! -f .env.production ]; then
  echo "[setup] copy .env.production.example to .env.production and edit secrets, then re-run."
  cp "$(dirname "$0")/.env.production.example" .env.production
  exit 1
fi

# Pull + start
docker compose --env-file .env.production -f "$(dirname "$0")/compose.production.yml" pull
docker compose --env-file .env.production -f "$(dirname "$0")/compose.production.yml" up -d

echo "[setup] done. Tail logs with:"
echo "  docker compose -f $(dirname "$0")/compose.production.yml logs -f backend caddy"
