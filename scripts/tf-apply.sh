#!/usr/bin/env bash
set -euo pipefail

# Ensure we have the required tools
if ! command -v tofu &>/dev/null || ! command -v sops &>/dev/null || ! command -v jq &>/dev/null || ! command -v yq &>/dev/null; then
  echo "📦 Launching in nix shell with opentofu, sops, jq, and yq..."
  exec nix shell nixpkgs#opentofu nixpkgs#jq nixpkgs#yq-go nixpkgs#sops -c "$0" "$@"
fi

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BOLD}${GREEN}🌐 Enterprise Cloudflare OpenTofu Setup${RESET}"
echo -e "=================================================="

# Check if secrets.yaml exists
SECRETS_FILE="nix-secrets/secrets.yaml"
if [ ! -f "$SECRETS_FILE" ]; then
  echo -e "${RED}❌ Secrets file not found at $SECRETS_FILE.${RESET}"
  exit 1
fi

echo -e "\n${BOLD}[1/4] Decrypting and checking secrets...${RESET}"
echo -e "${YELLOW}👉 Touch your YubiKey if it flashes to authorize decryption of secrets.yaml...${RESET}"
DECRYPTED_YAML=$(sops -d "$SECRETS_FILE")

# Check if we have api token and account id
API_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_api_token')
ACCOUNT_ID=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_account_id')

if [ "$API_TOKEN" = "null" ] || [ -z "$API_TOKEN" ] || [ "$ACCOUNT_ID" = "null" ] || [ -z "$ACCOUNT_ID" ]; then
  echo -e "${RED}❌ Missing cloudflare_api_token or cloudflare_account_id in secrets.yaml.${RESET}"
  echo -e "Please edit $SECRETS_FILE and add:"
  echo -e '  • cloudflare_api_token: "your-api-token"'
  echo -e '  • cloudflare_account_id: "your-account-id"'
  exit 1
fi

# Generate tunnel secret if missing
TUNNEL_SECRET=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_tunnel_secret')
if [ "$TUNNEL_SECRET" = "null" ] || [ -z "$TUNNEL_SECRET" ]; then
  echo -e "${YELLOW}Generating new 32-byte base64 tunnel secret...${RESET}"
  TUNNEL_SECRET=$(openssl rand -base64 32)
  sops --set "[\"cloudflare_tunnel_secret\"] \"$TUNNEL_SECRET\"" "$SECRETS_FILE"
  echo -e "🟢 Generated and saved cloudflare_tunnel_secret to secrets.yaml"
  # Refresh decrypted YAML state after write
  DECRYPTED_YAML=$(sops -d "$SECRETS_FILE")
fi

# Export variables for OpenTofu
export TF_VAR_cloudflare_api_token="$API_TOKEN"
export TF_VAR_cloudflare_account_id="$ACCOUNT_ID"
export TF_VAR_cloudflare_tunnel_secret="$TUNNEL_SECRET"

# --- GitHub provider inputs (sourced from sops) ---
# Reuses the existing spare `github_pat` sops key as the CI automation PAT
# distributed to repos as GH_PAT. `github_tf_token` is the admin PAT the
# provider authenticates with; `attic_push_token` becomes the ATTIC_PUSH_TOKEN
# secret. Add these keys to nix-secrets/secrets.yaml to manage GitHub via IaC.
GH_TF_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.github_tf_token')
GH_CI_PAT=$(echo "$DECRYPTED_YAML" | yq '.github_pat')
ATTIC_PUSH=$(echo "$DECRYPTED_YAML" | yq '.attic_push_token')

# Normalise missing keys ("null") to empty strings
[ "$GH_TF_TOKEN" = "null" ] && GH_TF_TOKEN=""
[ "$GH_CI_PAT" = "null" ] && GH_CI_PAT=""
[ "$ATTIC_PUSH" = "null" ] && ATTIC_PUSH=""

if [ -z "$GH_TF_TOKEN" ]; then
  echo -e "${YELLOW}⚠️  github_tf_token not set in secrets.yaml — GitHub resources will fail to authenticate."
  echo -e "    Add an admin PAT (classic: repo + workflow) under key 'github_tf_token' to manage GitHub via IaC.${RESET}"
fi

export TF_VAR_github_tf_token="$GH_TF_TOKEN"
export TF_VAR_github_ci_pat="$GH_CI_PAT"
export TF_VAR_attic_push_token="$ATTIC_PUSH"

# 2. OpenTofu Init & Apply
echo -e "\n${BOLD}[2/4] Initializing and applying OpenTofu plan...${RESET}"
cd terraform
tofu init
tofu apply -auto-approve

# 3. Capture Output
echo -e "\n${BOLD}[3/4] Capturing outputs...${RESET}"
TUNNEL_ID=$(tofu output -raw tunnel_id)
cd ..

if [ -z "$TUNNEL_ID" ]; then
  echo -e "${RED}❌ Failed to capture tunnel_id from OpenTofu output.${RESET}"
  exit 1
fi

echo -e "🟢 Tunnel ID: ${BOLD}$TUNNEL_ID${RESET}"

# Write Tunnel ID to secrets.yaml (if it changed)
CURRENT_TUNNEL_ID=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_tunnel_id')
if [ "$CURRENT_TUNNEL_ID" != "$TUNNEL_ID" ]; then
  echo -e "Updating cloudflare_tunnel_id in secrets.yaml..."
  sops --set "[\"cloudflare_tunnel_id\"] \"$TUNNEL_ID\"" "$SECRETS_FILE"
  echo -e "🟢 Updated cloudflare_tunnel_id in secrets.yaml"
fi

# 4. Success
echo -e "\n${BOLD}[4/4] OpenTofu Cloudflare Setup Complete!${RESET}"
echo -e "--------------------------------------------------"
echo -e "Your Cloudflare Tunnel and CNAME wildcard DNS records have been deployed."
echo -e "NixOS is now ready to build and run the tunnel service."
echo -e "\nTo deploy to NixOS, run:"
echo -e "  • ${BOLD}just git::save \"feat: add cloudflare IaC config\"${RESET}"
echo -e "  • ${BOLD}just maintenance::apply${RESET}"
echo -e "--------------------------------------------------"
