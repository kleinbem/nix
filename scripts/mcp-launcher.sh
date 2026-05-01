#!/usr/bin/env bash
# MCP Secure Launcher - V1.0
# Handles identity-based, short-lived credentials for MCP servers.

SERVER_NAME=$1
shift # The rest of the arguments are the command to run

# Colors for logging (to stderr so we don't break JSON-RPC)
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[MCP-SECURE:$SERVER_NAME]${NC} $1" >&2; }

case $SERVER_NAME in
github)
  log "Requesting short-lived GitHub token..."
  # In a full GitHub App setup, we'd use a tool to exchange a private key for a token.
  # For now, we'll pull the PAT from SOPS, but we keep it in memory only.
  TOKEN=$(sops --decrypt --extract '["github_pat"]' /home/martin/Develop/github.com/kleinbem/nix/nix-config/hosts/nixos-nvme/secrets.yaml)
  export GITHUB_PERSONAL_ACCESS_TOKEN="$TOKEN"
  ;;
brave-search)
  log "Injecting Brave API Key..."
  TOKEN=$(sops --decrypt --extract '["brave_api_key"]' /home/martin/Develop/github.com/kleinbem/nix/nix-config/hosts/nixos-nvme/secrets.yaml)
  export BRAVE_API_KEY="$TOKEN"
  ;;
esac

# Execute the actual server
log "Launching server..."
exec "$@"
