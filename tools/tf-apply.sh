#!/usr/bin/env bash
set -euo pipefail

# Usage: tf-apply.sh [--plan-only | --migrate-tunnel | --migrate-state]
#   --plan-only       Run `tofu plan` and exit without applying.
#   --migrate-tunnel  One-shot: rebind tunnel state from the deprecated
#                     `cloudflare_tunnel.nixos_nvme` address to
#                     `cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme`
#                     via `tofu state rm` + `tofu import`. Idempotent: skips
#                     cleanly if state is already at the new address.
#   --migrate-state   One-shot: copy local terraform.tfstate into the R2
#                     backend (backend.tf) via `tofu init -migrate-state`.
#                     The local tfstate files stay behind as a fallback copy.
MODE="apply"
PASSTHROUGH=()
SAW_DDASH=0
for arg in "$@"; do
  if [ $SAW_DDASH -eq 1 ]; then
    PASSTHROUGH+=("$arg")
    continue
  fi
  case "$arg" in
  --plan-only | --plan) MODE="plan" ;;
  --migrate-tunnel) MODE="migrate-tunnel" ;;
  --migrate-state) MODE="migrate-state" ;;
  --) SAW_DDASH=1 ;;
  -h | --help)
    echo "Usage: $0 [--plan-only | --migrate-tunnel | --migrate-state] [-- <tofu-args>...]"
    echo "  Default:          decrypt sops, run 'tofu apply -auto-approve', write back tunnel_id."
    echo "  --plan-only:      decrypt sops, run 'tofu plan', exit."
    echo "  --migrate-tunnel: rebind tunnel state to the new resource address."
    echo "  --migrate-state:  one-shot copy of local terraform.tfstate into the R2 backend."
    echo "  -- <tofu-args>:   pass everything after -- straight to 'tofu apply'."
    # shellcheck disable=SC2016  # literal $PASSTHROUGH is the documented behavior
    echo '                    (default apply: tofu apply -auto-approve $PASSTHROUGH)'
    echo "                    Example: $0 -- -target='github_actions_secret.ci' -auto-approve"
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

# kleinbem-secrets (cutover 2026-08-08, replaces nix-secrets) scopes
# credentials per-consumer, so this script reads from several files rather
# than one flat secrets.yaml. kleinbem-secrets is a flat sibling of nix/,
# not nested under it, so resolve from this script's own location rather
# than assuming the caller's cwd.
SECRETS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/kleinbem-secrets"
TERRAFORM_FILE="$SECRETS_ROOT/infra/terraform.yaml"
SHARED_FILE="$SECRETS_ROOT/nix/shared.yaml"
COREPI_FILE="$SECRETS_ROOT/nix/per-host/core-pi.yaml"
ORIN_FILE="$SECRETS_ROOT/nix/per-host/orin-nano.yaml"
for f in "$TERRAFORM_FILE" "$SHARED_FILE" "$COREPI_FILE" "$ORIN_FILE"; do
  if [ ! -f "$f" ]; then
    echo -e "${RED}❌ Secrets file not found at $f.${RESET}"
    exit 1
  fi
done

echo -e "\n${BOLD}[1/4] Decrypting and checking secrets...${RESET}"
echo -e "${YELLOW}👉 Touch your YubiKey if it flashes — up to 4 scoped files to decrypt...${RESET}"
DECRYPTED_YAML=$(sops -d "$TERRAFORM_FILE")
SHARED_YAML=$(sops -d "$SHARED_FILE")
COREPI_YAML=$(sops -d "$COREPI_FILE")
ORIN_YAML=$(sops -d "$ORIN_FILE")

# Check if we have api token and account id
API_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_api_token')
ACCOUNT_ID=$(echo "$COREPI_YAML" | yq '.cloudflare_account_id')

if [ "$API_TOKEN" = "null" ] || [ -z "$API_TOKEN" ] || [ "$ACCOUNT_ID" = "null" ] || [ -z "$ACCOUNT_ID" ]; then
  echo -e "${RED}❌ Missing cloudflare_api_token (infra/terraform.yaml) or cloudflare_account_id (nix/per-host/core-pi.yaml).${RESET}"
  echo -e "Please add:"
  echo -e "  • cloudflare_api_token to $TERRAFORM_FILE"
  echo -e "  • cloudflare_account_id to $COREPI_FILE"
  exit 1
fi

# Generate tunnel secret if missing. Lives in core-pi's own scope — it's the
# host that runs the tunnel, same file hosts/core-pi/secrets.nix reads
# cloudflare_tunnel_secret from.
TUNNEL_SECRET=$(echo "$COREPI_YAML" | yq '.cloudflare_tunnel_secret')
if [ "$TUNNEL_SECRET" = "null" ] || [ -z "$TUNNEL_SECRET" ]; then
  echo -e "${YELLOW}Generating new 32-byte base64 tunnel secret...${RESET}"
  TUNNEL_SECRET=$(openssl rand -base64 32)
  sops --set "[\"cloudflare_tunnel_secret\"] \"$TUNNEL_SECRET\"" "$COREPI_FILE"
  echo -e "🟢 Generated and saved cloudflare_tunnel_secret to nix/per-host/core-pi.yaml"
  # Refresh decrypted YAML state after write
  COREPI_YAML=$(sops -d "$COREPI_FILE")
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
# actions/create-github-app-token at runtime). Those two live in
# nix/shared.yaml (every NixOS host's scope), not infra/terraform.yaml.
# `attic_push_token` becomes the ATTIC_PUSH_TOKEN secret — lives in
# orin-nano's own per-host scope.
GH_TF_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.github_tf_token')
GH_APP_ID=$(echo "$SHARED_YAML" | yq '.github_app_id')
GH_APP_PRIVATE_KEY=$(echo "$SHARED_YAML" | yq '.github_app_private_key')
ATTIC_PUSH=$(echo "$ORIN_YAML" | yq '.attic_push_token')
NETBIRD_KEY=$(echo "$SHARED_YAML" | yq '.netbird_setup_key')
NETBIRD_KEY_EPHEMERAL=$(echo "$DECRYPTED_YAML" | yq '.netbird_setup_key_ephemeral')
NTFY_DEPLOY_TOPIC=$(echo "$SHARED_YAML" | yq '.ntfy_deploy_topic')
NTFY_ALERT_TOPIC=$(echo "$DECRYPTED_YAML" | yq '.ntfy_alert_topic')

# --- Google Cloud (infra/google.tf) ---
# Bootstrap service-account key (base64 JSON), manually created via gcloud —
# see infra/google.tf's header comment. Not itself Terraform-managed.
GOOGLE_SA_KEY=$(echo "$DECRYPTED_YAML" | yq '.google_service_account_key')

# Normalise missing keys ("null") to empty strings
[ "$GH_TF_TOKEN" = "null" ] && GH_TF_TOKEN=""
[ "$GH_APP_ID" = "null" ] && GH_APP_ID=""
[ "$GH_APP_PRIVATE_KEY" = "null" ] && GH_APP_PRIVATE_KEY=""
[ "$ATTIC_PUSH" = "null" ] && ATTIC_PUSH=""
[ "$NETBIRD_KEY" = "null" ] && NETBIRD_KEY=""
[ "$NETBIRD_KEY_EPHEMERAL" = "null" ] && NETBIRD_KEY_EPHEMERAL=""
[ "$NTFY_DEPLOY_TOPIC" = "null" ] && NTFY_DEPLOY_TOPIC=""
[ "$NTFY_ALERT_TOPIC" = "null" ] && NTFY_ALERT_TOPIC=""
[ "$GOOGLE_SA_KEY" = "null" ] && GOOGLE_SA_KEY=""

if [ -z "$GH_TF_TOKEN" ]; then
  echo -e "${YELLOW}⚠️  github_tf_token not set in $TERRAFORM_FILE — GitHub resources will fail to authenticate."
  echo -e "    Add a fine-grained PAT (Administration + Issues + Secrets: R/W on the nix-* repos) under key 'github_tf_token' to manage GitHub via IaC.${RESET}"
fi

if [ -z "$GH_APP_ID" ] || [ -z "$GH_APP_PRIVATE_KEY" ]; then
  echo -e "${YELLOW}⚠️  github_app_id or github_app_private_key not set in $SHARED_FILE — CI workflows that mint App tokens will fail.${RESET}"
fi

if [ -z "$GOOGLE_SA_KEY" ]; then
  echo -e "${YELLOW}⚠️  google_service_account_key not set in $TERRAFORM_FILE — infra/google.tf resources will fail to authenticate.${RESET}"
fi

export TF_VAR_github_tf_token="$GH_TF_TOKEN"
export TF_VAR_github_app_id="$GH_APP_ID"
export TF_VAR_github_app_private_key="$GH_APP_PRIVATE_KEY"
export TF_VAR_attic_push_token="$ATTIC_PUSH"
export TF_VAR_netbird_setup_key="$NETBIRD_KEY"
export TF_VAR_netbird_setup_key_ephemeral="$NETBIRD_KEY_EPHEMERAL"
export TF_VAR_ntfy_deploy_topic="$NTFY_DEPLOY_TOPIC"
export TF_VAR_ntfy_alert_topic="$NTFY_ALERT_TOPIC"
export TF_VAR_google_service_account_key="$GOOGLE_SA_KEY"

# 2. OpenTofu Init & Plan/Apply
echo -e "\n${BOLD}[2/4] Initializing OpenTofu...${RESET}"

# --- R2 state backend config (see infra/backend.tf) ---
# Backend blocks can't reference variables, so the endpoint + R2 access key are
# fed via a generated, gitignored backend-config file. Credentials come from
# sops (r2_state_access_key_id / r2_state_secret_access_key), falling back to
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env. They are deliberately NOT
# exported as env vars: the aws provider (aws-ses.tf) authenticates to real AWS
# via ambient env and must not pick up R2 keys.
R2_KEY_ID=$(echo "$DECRYPTED_YAML" | yq '.r2_state_access_key_id')
R2_KEY_SECRET=$(echo "$DECRYPTED_YAML" | yq '.r2_state_secret_access_key')
[ "$R2_KEY_ID" = "null" ] && R2_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
[ "$R2_KEY_SECRET" = "null" ] && R2_KEY_SECRET="${AWS_SECRET_ACCESS_KEY:-}"

export TF_VAR_r2_state_access_key_id="$R2_KEY_ID"
export TF_VAR_r2_state_secret_access_key="$R2_KEY_SECRET"

# --- State encryption passphrase (see infra/encryption.tf) ---
# Injected via the TF_ENCRYPTION config merge so the committed encryption.tf
# never contains the secret. pbkdf2 requires >= 16 chars.
TOFU_STATE_PASSPHRASE=$(echo "$DECRYPTED_YAML" | yq '.tofu_state_passphrase')
[ "$TOFU_STATE_PASSPHRASE" = "null" ] && TOFU_STATE_PASSPHRASE=""
if [ -z "$TOFU_STATE_PASSPHRASE" ]; then
  echo -e "${RED}❌ No state-encryption passphrase (infra/encryption.tf is active).${RESET}"
  echo -e "Generate one and add it to sops:"
  echo -e "  ${BOLD}openssl rand -base64 32${RESET}"
  echo -e "  ${BOLD}sops $TERRAFORM_FILE${RESET} → tofu_state_passphrase: <value>"
  exit 1
fi
export TF_ENCRYPTION="key_provider \"pbkdf2\" \"state_key\" { passphrase = \"${TOFU_STATE_PASSPHRASE}\" }"

if [ -z "$R2_KEY_ID" ] || [ -z "$R2_KEY_SECRET" ]; then
  echo -e "${RED}❌ No R2 access key for the state backend.${RESET}"
  echo -e "Create one (Cloudflare dashboard → R2 → Manage R2 API Tokens → Object Read & Write,"
  echo -e "scoped to the ${BOLD}kleinbem-tofu-state${RESET} bucket), then either:"
  echo -e "  • add it to sops: ${BOLD}sops $TERRAFORM_FILE${RESET} → r2_state_access_key_id / r2_state_secret_access_key"
  echo -e "  • or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY for this run."
  exit 1
fi

cd infra
rm -f .r2-backend.hcl
touch .r2-backend.hcl
chmod 600 .r2-backend.hcl
cat >.r2-backend.hcl <<EOF
endpoints  = { s3 = "https://${ACCOUNT_ID}.r2.cloudflarestorage.com" }
access_key = "${R2_KEY_ID}"
secret_key = "${R2_KEY_SECRET}"
EOF

if [ "$MODE" = "migrate-state" ]; then
  echo -e "${YELLOW}Migrating local terraform.tfstate into the R2 backend (kleinbem-tofu-state/infra.tfstate)...${RESET}"
  echo -e "${YELLOW}Local tfstate files stay behind, gitignored, as a fallback copy.${RESET}"
  tofu init -backend-config=.r2-backend.hcl -migrate-state -force-copy
  echo -e "\n${BOLD}${GREEN}✅ State migrated to R2. Verify with: $0 --plan-only (expect no changes).${RESET}"
  exit 0
fi

tofu init -input=false -backend-config=.r2-backend.hcl

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
if [ ${#PASSTHROUGH[@]} -gt 0 ]; then
  echo -e "${YELLOW}Passthrough args: ${PASSTHROUGH[*]}${RESET}"
  tofu apply "${PASSTHROUGH[@]}"
else
  tofu apply -auto-approve
fi

# 3. Capture Output
# Both paths fall through to the same capture logic now — a targeted/
# passthrough apply used to skip this entirely (comment used to live here:
# "tofu output -raw tunnel_id would error out if the tunnel wasn't part of
# the apply set"), which meant OTHER outputs from a targeted apply (e.g.
# juan_gemini_api_key from a Google-only -target run) never got captured
# either. Fixed by making every capture graceful instead of skipping the
# whole step — read with `|| echo ""`, only act if non-empty. A first-ever
# apply narrowly targeted away from the tunnel just silently skips writing
# tunnel_id back, exactly like the Gemini capture already did for a targeted
# apply that didn't include it.
echo -e "\n${BOLD}[3/4] Capturing outputs...${RESET}"
TUNNEL_ID=$(tofu output -raw tunnel_id 2>/dev/null || echo "")
GEMINI_API_KEY_JUAN=$(tofu output -raw juan_gemini_api_key 2>/dev/null || echo "")
cd ..

if [ -z "$TUNNEL_ID" ]; then
  echo -e "${YELLOW}⚠️  tunnel_id not present in state (narrow apply that didn't include it?) — skipping tunnel-id write-back.${RESET}"
else
  echo -e "🟢 Tunnel ID: ${BOLD}$TUNNEL_ID${RESET}"

  # Write Tunnel ID to core-pi's own scope (if it changed) — same file
  # cloudflare_tunnel_secret above lives in, and what hosts/core-pi/secrets.nix
  # reads cloudflare_tunnel_id from.
  CURRENT_TUNNEL_ID=$(echo "$COREPI_YAML" | yq '.cloudflare_tunnel_id')
  if [ "$CURRENT_TUNNEL_ID" != "$TUNNEL_ID" ]; then
    echo -e "Updating cloudflare_tunnel_id in nix/per-host/core-pi.yaml..."
    sops --set "[\"cloudflare_tunnel_id\"] \"$TUNNEL_ID\"" "$COREPI_FILE"
    echo -e "🟢 Updated cloudflare_tunnel_id in nix/per-host/core-pi.yaml"
  fi
fi

# Write juan's Gemini API key as a keyed value in kleinbem-secrets'
# one-YAML-per-persona file (cutover 2026-08-08 — was its own binary-mode
# sopsFile under the old nix-secrets/personas/<name>/<key> layout; matches
# how hosts/mac-mini/secrets.nix's juan_gemini_api_key sopsFile+key already
# expects it). If more personas get their own google_apikeys_key in
# infra/google.tf, repeat this block per persona — don't try to generalize
# into a loop until there's a 3rd one.
if [ -n "$GEMINI_API_KEY_JUAN" ]; then
  JUAN_YAML="$SECRETS_ROOT/personas/juan.yaml"
  GEMINI_WORK="$(mktemp -d /dev/shm/tf-apply-gemini-XXXXXX)"
  trap 'find "$GEMINI_WORK" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "$GEMINI_WORK"' EXIT
  sops -d "$JUAN_YAML" >"$GEMINI_WORK/juan.yaml"
  printf '%s' "$GEMINI_API_KEY_JUAN" >"$GEMINI_WORK/gemini_api_key.txt"
  GEMINI_KEY_PATH="$GEMINI_WORK/gemini_api_key.txt" yq -i \
    '.gemini_api_key = load_str(strenv(GEMINI_KEY_PATH))' "$GEMINI_WORK/juan.yaml"
  sops --config "$SECRETS_ROOT/.sops.yaml" --filename-override "$JUAN_YAML" \
    -e "$GEMINI_WORK/juan.yaml" >"$GEMINI_WORK/juan-enc.yaml"
  mv "$GEMINI_WORK/juan-enc.yaml" "$JUAN_YAML"
  echo -e "🟢 Wrote juan's Gemini API key to kleinbem-secrets/personas/juan.yaml"
fi

# 4. Success
echo -e "\n${BOLD}[4/4] OpenTofu Apply Complete!${RESET}"
echo -e "--------------------------------------------------"
if [ ${#PASSTHROUGH[@]} -gt 0 ]; then
  echo -e "Targeted apply finished (${PASSTHROUGH[*]})."
else
  echo -e "Your Cloudflare Tunnel and CNAME wildcard DNS records have been deployed."
  echo -e "NixOS is now ready to build and run the tunnel service."
  echo -e "\nTo deploy to NixOS, run:"
  echo -e "  • ${BOLD}just git::save \"feat: add cloudflare IaC config\"${RESET}"
  echo -e "  • ${BOLD}just maintenance::apply${RESET}"
fi
echo -e "--------------------------------------------------"
