#!/usr/bin/env bash
set -euo pipefail

# Usage: tf-apply.sh [--plan-only | --migrate-tunnel]
#   --plan-only       Run `tofu plan` and exit without applying.
#   --migrate-tunnel  One-shot: rebind tunnel state from the deprecated
#                     `cloudflare_tunnel.nixos_nvme` address to
#                     `cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme`
#                     via `tofu state rm` + `tofu import`. Idempotent: skips
#                     cleanly if state is already at the new address.
MODE="apply"
for arg in "$@"; do
  case "$arg" in
  --plan-only | --plan) MODE="plan" ;;
  --migrate-tunnel) MODE="migrate-tunnel" ;;
  -h | --help)
    echo "Usage: $0 [--plan-only | --migrate-tunnel]"
    echo "  Default:          decrypt sops, run 'tofu apply -auto-approve', write back tunnel_id."
    echo "  --plan-only:      decrypt sops, run 'tofu plan', exit."
    echo "  --migrate-tunnel: rebind tunnel state to the new resource address."
    exit 0
    ;;
  esac
done

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
# `github_tf_token` is the admin PAT the provider authenticates with.
# `github_app_id` + `github_app_private_key` are the GitHub App credentials
# distributed to CI repos as APP_ID / APP_PRIVATE_KEY (replaces the retired
# long-lived GH_PAT — workflows mint short-lived tokens via
# actions/create-github-app-token at runtime).
# `attic_push_token` becomes the ATTIC_PUSH_TOKEN secret.
GH_TF_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.github_tf_token')
GH_APP_ID=$(echo "$DECRYPTED_YAML" | yq '.github_app_id')
GH_APP_PRIVATE_KEY=$(echo "$DECRYPTED_YAML" | yq '.github_app_private_key')
ATTIC_PUSH=$(echo "$DECRYPTED_YAML" | yq '.attic_push_token')

# Normalise missing keys ("null") to empty strings
[ "$GH_TF_TOKEN" = "null" ] && GH_TF_TOKEN=""
[ "$GH_APP_ID" = "null" ] && GH_APP_ID=""
[ "$GH_APP_PRIVATE_KEY" = "null" ] && GH_APP_PRIVATE_KEY=""
[ "$ATTIC_PUSH" = "null" ] && ATTIC_PUSH=""

if [ -z "$GH_TF_TOKEN" ]; then
  echo -e "${YELLOW}⚠️  github_tf_token not set in secrets.yaml — GitHub resources will fail to authenticate."
  echo -e "    Add a fine-grained PAT (Administration + Issues + Secrets: R/W on the nix-* repos) under key 'github_tf_token' to manage GitHub via IaC.${RESET}"
fi

if [ -z "$GH_APP_ID" ] || [ -z "$GH_APP_PRIVATE_KEY" ]; then
  echo -e "${YELLOW}⚠️  github_app_id or github_app_private_key not set in secrets.yaml — CI workflows that mint App tokens will fail.${RESET}"
fi

export TF_VAR_github_tf_token="$GH_TF_TOKEN"
export TF_VAR_github_app_id="$GH_APP_ID"
export TF_VAR_github_app_private_key="$GH_APP_PRIVATE_KEY"
export TF_VAR_attic_push_token="$ATTIC_PUSH"

# 2. OpenTofu Init & Plan/Apply
echo -e "\n${BOLD}[2/4] Initializing OpenTofu...${RESET}"
cd terraform
tofu init

if [ "$MODE" = "plan" ]; then
  echo -e "\n${BOLD}🔎 Running plan only (no changes will be applied)...${RESET}"
  tofu plan
  echo -e "\n${BOLD}${GREEN}✅ Plan complete. Re-run without --plan-only to apply.${RESET}"
  exit 0
fi

if [ "$MODE" = "migrate-tunnel" ]; then
  OLD_ADDR="cloudflare_tunnel.nixos_nvme"
  NEW_ADDR="cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme"

  # Idempotency: if new address is already in state, nothing to do.
  if tofu state list 2>/dev/null | grep -qx "$NEW_ADDR"; then
    echo -e "${GREEN}🟢 ${NEW_ADDR} is already in state — nothing to do.${RESET}"
    exit 0
  fi

  if ! tofu state list 2>/dev/null | grep -qx "$OLD_ADDR"; then
    echo -e "${RED}❌ Neither ${OLD_ADDR} nor ${NEW_ADDR} is in state. Aborting — investigate manually.${RESET}"
    exit 1
  fi

  # Extract the live tunnel ID from the old state entry before we remove it.
  TUNNEL_ID=$(tofu state show "$OLD_ADDR" | awk '/^[[:space:]]*id[[:space:]]*=/{ gsub(/"/, "", $3); print $3; exit }')
  if [ -z "$TUNNEL_ID" ]; then
    echo -e "${RED}❌ Could not extract tunnel id from old state entry. Aborting.${RESET}"
    exit 1
  fi
  echo -e "${YELLOW}👉 Extracted tunnel id: ${BOLD}${TUNNEL_ID}${RESET}"

  echo -e "${YELLOW}Removing ${OLD_ADDR} from state (no Cloudflare-side change)...${RESET}"
  tofu state rm "$OLD_ADDR"

  echo -e "${YELLOW}Importing live tunnel as ${NEW_ADDR}...${RESET}"
  tofu import "$NEW_ADDR" "${TF_VAR_cloudflare_account_id}/${TUNNEL_ID}"

  echo -e "\n${BOLD}${GREEN}✅ Tunnel state migrated. Run \`$0 --plan-only\` to verify zero diff.${RESET}"
  exit 0
fi

echo -e "\n${BOLD}Applying OpenTofu plan...${RESET}"
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
