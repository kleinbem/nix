#!/usr/bin/env bash
# tools/phone-ssh-deploy.sh
# Deploys the repos to Nix-on-Droid over SSH, in the same flat $HOME layout as
# phone-deploy.sh, then runs phone-activate.sh on the phone.
# Usage: phone-ssh-deploy.sh <host> [port]   (sshd in Nix-on-Droid listens on 8022)

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <host> [port]" >&2
  exit 1
fi
PHONE_HOST=$1
PHONE_PORT=${2:-8022}

NIX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(dirname "$NIX_ROOT")"
REPOS=(nix-config nix-presets nix-devshells nix-hardware nix-packages nix-templates kleinbem-secrets)
SSH=(ssh -p "$PHONE_PORT")

echo "🌐 Deploying to phone at $PHONE_HOST:$PHONE_PORT..."

# No trailing slash on the sources: each lands as ~/<name>, and --delete only
# prunes inside those. .git is excluded, so the phone's own git init survives.
echo "📦 Syncing files via rsync..."
rsync -az --delete -h --info=progress2 \
  --exclude ".git/" \
  --exclude ".jj/" \
  --exclude ".direnv/" \
  --exclude ".devenv/" \
  --exclude "result" \
  --exclude "*.tar.gz" \
  -e "${SSH[*]}" \
  "${REPOS[@]/#/$WORKSPACE_ROOT/}" "$NIX_ROOT/tools" \
  "$PHONE_HOST:"

echo "🚀 Activating configuration on phone..."
# shellcheck disable=SC2016 # $HOME expands on the phone
"${SSH[@]}" "$PHONE_HOST" 'bash "$HOME/tools/phone-activate.sh"'

echo "✅ Phone deployment complete!"
