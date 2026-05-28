#!/usr/bin/env bash
# scripts/phone-ssh-deploy.sh
# Deploys the meta-repo to Nix-on-Droid via SSH

set -e

# Configuration
PHONE_IP=${1:-"192.168.178.69"}
PHONE_PORT=${2:-"8022"}
# shellcheck disable=SC2088
TARGET_DIR="~/nix-config"

echo "🌐 Deploying to phone at $PHONE_IP:$PHONE_PORT..."

# 1. Sync the meta-repo (excluding large/unnecessary items)
echo "📦 Syncing files via Rsync..."
rsync -avz --delete -h --progress --info=progress2 \
  --exclude ".git/" \
  --exclude ".direnv/" \
  --exclude "result" \
  --exclude "*.tar.gz" \
  -e "ssh -p $PHONE_PORT" \
  ./ "$PHONE_IP:$TARGET_DIR/"

# 2. Trigger activation remotely
echo "🚀 Activating configuration on phone..."
ssh -p "$PHONE_PORT" "$PHONE_IP" "bash $TARGET_DIR/scripts/phone-activate.sh"

echo "✅ Phone deployment complete!"
