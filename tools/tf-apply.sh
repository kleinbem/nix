#!/usr/bin/env bash
set -euo pipefail

# Decrypts sops, runs tofu in infra/ and writes outputs back to kleinbem-secrets.
# Modes: see --help.
# Ensure we have the required tools
if ! command -v tofu &>/dev/null || ! command -v sops &>/dev/null || ! command -v jq &>/dev/null || ! command -v yq &>/dev/null; then
  echo "📦 Launching in nix shell with opentofu, sops, jq, and yq..."
  exec nix shell nixpkgs#opentofu nixpkgs#jq nixpkgs#yq-go nixpkgs#sops -c "$0" "$@"
fi

MODE="apply"
PASSTHROUGH=()
SAW_DDASH=0
while [ $# -gt 0 ]; do
  if [ $SAW_DDASH -eq 1 ]; then
    PASSTHROUGH+=("$1")
    shift
    continue
  fi
  case "$1" in
  --plan-only | --plan) MODE="plan"; shift ;;
  --migrate-tunnel) MODE="migrate-tunnel"; shift ;;
  --migrate-state) MODE="migrate-state"; shift ;;
  --state-rm)
    MODE="state-rm"
    shift
    while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
      PASSTHROUGH+=("$1")
      shift
    done
    ;;
  --exec)
    MODE="exec"
    shift
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
      PASSTHROUGH+=("$1")
      shift
    done
    ;;
  --) SAW_DDASH=1; shift ;;
  -h | --help)
    echo "Usage: $0 [--plan-only | --state-rm <resource...> | --exec <tofu-cmd...> | --migrate-tunnel | --migrate-state] [-- <tofu-args>...]"
    echo "  Default:          decrypt sops, plan, apply it unless it deletes or replaces anything"
    echo "                    (ALLOW_DESTROY=1 allows that), write back tunnel_id."
    echo "  --plan-only:      decrypt sops, run 'tofu plan', exit."
    echo "  --state-rm:       remove one or more resources from OpenTofu state."
    echo "  --exec:           run arbitrary tofu command with decrypted state & backend environment."
    echo "  --migrate-tunnel: rebind tunnel state to the new resource address."
    echo "  --migrate-state:  one-shot copy of local terraform.tfstate into the R2 backend."
    echo "  -- <tofu-args>:   pass everything after -- to 'tofu plan' (-auto-approve: skip the prompt)."
    echo "                    Example: $0 -- -target='github_actions_secret.ci' -auto-approve"
    exit 0
    ;;
  *)
    PASSTHROUGH+=("$1")
    shift
    ;;
  esac
done

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BOLD}${GREEN}🌐 Enterprise Cloudflare OpenTofu Setup${RESET}"
echo -e "=================================================="

# Refresh infra/*.json from nix-config; soft-fail so a missing checkout
# doesn't block a creds-only apply.
"$(dirname "${BASH_SOURCE[0]}")/gen-iac-data.sh" || \
  echo -e "${YELLOW}⚠️  gen-iac-data.sh failed — proceeding with the committed infra/*.json${RESET}"

# kleinbem-secrets scopes secrets per consumer, so several files are read.
# It's a sibling of nix/, resolved from this script's location, not the cwd.
SECRETS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/kleinbem-secrets"
GUARDED_APPLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tofu-guarded-apply.sh"
TERRAFORM_FILE="$SECRETS_ROOT/infra/terraform.yaml"
SHARED_FILE="$SECRETS_ROOT/nix/shared.yaml"
COREPI_FILE="$SECRETS_ROOT/nix/per-host/core-pi.yaml"
ORIN_FILE="$SECRETS_ROOT/nix/per-host/orin-nano.yaml"
# Read from their single source rather than copied into infra/terraform.yaml.
AUTHENTIK_FILE="$SECRETS_ROOT/nix/per-container/authentik.yaml"
# Holds the Google OAuth client Authentik uses (see infra/google.tf).
KLEINBEM_AUTH_FILE="$SECRETS_ROOT/nix/per-container/kleinbem-auth.yaml"
for f in "$TERRAFORM_FILE" "$SHARED_FILE" "$COREPI_FILE" "$ORIN_FILE" "$AUTHENTIK_FILE" "$KLEINBEM_AUTH_FILE"; do
  if [ ! -f "$f" ]; then
    echo -e "${RED}❌ Secrets file not found at $f.${RESET}"
    exit 1
  fi
done

echo -e "\n${BOLD}[1/4] Decrypting and checking secrets...${RESET}"
echo -e "${YELLOW}👉 Touch your YubiKey if it flashes — up to 6 scoped files to decrypt...${RESET}"
DECRYPTED_YAML=$(sops -d "$TERRAFORM_FILE")
SHARED_YAML=$(sops -d "$SHARED_FILE")
COREPI_YAML=$(sops -d "$COREPI_FILE")
ORIN_YAML=$(sops -d "$ORIN_FILE")
AUTHENTIK_YAML=$(sops -d "$AUTHENTIK_FILE")
KLEINBEM_AUTH_YAML=$(sops -d "$KLEINBEM_AUTH_FILE")
AUTHENTIK_API_TOKEN=$(echo "$AUTHENTIK_YAML" | yq '.authentik_bootstrap_api_token')
GOOGLE_CLIENT_ID=$(echo "$KLEINBEM_AUTH_YAML" | yq '.google_client_id')
GOOGLE_CLIENT_SECRET=$(echo "$KLEINBEM_AUTH_YAML" | yq '.google_client_secret')

# Check if we have api token and account id
API_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_api_token')
ACCOUNT_ID=$(echo "$COREPI_YAML" | yq '.cloudflare_account_id')
# Pages-only token for kleinbem-site's CI (cloudflare-pages.tf), kept separate
# from cloudflare_api_token.
PAGES_DEPLOY_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.cloudflare_pages_deploy_token')

if [ "$API_TOKEN" = "null" ] || [ -z "$API_TOKEN" ] || [ "$ACCOUNT_ID" = "null" ] || [ -z "$ACCOUNT_ID" ]; then
  echo -e "${RED}❌ Missing cloudflare_api_token (infra/terraform.yaml) or cloudflare_account_id (nix/per-host/core-pi.yaml).${RESET}"
  echo -e "Please add:"
  echo -e "  • cloudflare_api_token to $TERRAFORM_FILE"
  echo -e "  • cloudflare_account_id to $COREPI_FILE"
  exit 1
fi

if [ "$PAGES_DEPLOY_TOKEN" = "null" ] || [ -z "$PAGES_DEPLOY_TOKEN" ]; then
  echo -e "${RED}❌ Missing cloudflare_pages_deploy_token ($TERRAFORM_FILE).${RESET}"
  echo -e "This is a separate, narrower token from cloudflare_api_token — Cloudflare Pages: Edit only,"
  echo -e "for kleinbem-site's CI to deploy with. Add it with:"
  echo -e "  sops --set '[\"cloudflare_pages_deploy_token\"] \"<token value>\"' $TERRAFORM_FILE"
  exit 1
fi

# Generate the tunnel secret if missing, in core-pi's file (it runs the tunnel).
TUNNEL_SECRET=$(echo "$COREPI_YAML" | yq '.cloudflare_tunnel_secret')
if [ "$TUNNEL_SECRET" = "null" ] || [ -z "$TUNNEL_SECRET" ]; then
  echo -e "${YELLOW}Generating new 32-byte base64 tunnel secret...${RESET}"
  TUNNEL_SECRET=$(openssl rand -base64 32)
  sops --set "[\"cloudflare_tunnel_secret\"] \"$TUNNEL_SECRET\"" "$COREPI_FILE"
  echo -e "🟢 Generated and saved cloudflare_tunnel_secret to nix/per-host/core-pi.yaml"
  # Refresh decrypted YAML state after write
  COREPI_YAML=$(sops -d "$COREPI_FILE")
fi

# Generate kleinbem-site's session secret if missing; only its Pages Functions
# use it, so it lives in infra/terraform.yaml.
SESSION_SECRET=$(echo "$DECRYPTED_YAML" | yq '.kleinbem_site_session_secret')
if [ "$SESSION_SECRET" = "null" ] || [ -z "$SESSION_SECRET" ]; then
  echo -e "${YELLOW}Generating new kleinbem-site session-signing secret...${RESET}"
  SESSION_SECRET=$(openssl rand -hex 32)
  sops --set "[\"kleinbem_site_session_secret\"] \"$SESSION_SECRET\"" "$TERRAFORM_FILE"
  echo -e "🟢 Generated and saved kleinbem_site_session_secret to infra/terraform.yaml"
  DECRYPTED_YAML=$(sops -d "$TERRAFORM_FILE")
fi

# Export variables for OpenTofu
export TF_VAR_cloudflare_api_token="$API_TOKEN"
export TF_VAR_cloudflare_account_id="$ACCOUNT_ID"
export TF_VAR_cloudflare_tunnel_secret="$TUNNEL_SECRET"
export TF_VAR_kleinbem_site_session_secret="$SESSION_SECRET"
export TF_VAR_cloudflare_pages_deploy_token="$PAGES_DEPLOY_TOKEN"

echo -e "\n${BOLD}${YELLOW}🔍 Cloudflare Token & Zero Trust Diagnostics:${RESET}"
echo -n "  • Token status:   "
curl -s -H "Authorization: Bearer $API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify | jq -c '{id: .result.id, status: .result.status, success: .success, errors: .errors}'
echo -n "  • Zero Trust Org: "
curl -s -H "Authorization: Bearer $API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/organizations" | jq -c '{name: .result.name, auth_domain: .result.auth_domain, success: .success, errors: .errors}'
echo -n "  • Access IdPs:    "
curl -s -H "Authorization: Bearer $API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/identity_providers" | jq -c '{count: (.result | length), success: .success, errors: .errors}'
echo -n "  • Web Analytics:  "
curl -s -H "Authorization: Bearer $API_TOKEN" "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/rum/site_info/list" | jq -c '{count: (.result | length), success: .success, errors: .errors}'
# Report only whether the cloudflare-access client secret exists, never the
# value: this output gets pasted into chats and issues.
echo -n "  • Authentik OIDC: "
curl -s -H "Authorization: Bearer $AUTHENTIK_API_TOKEN" "https://auth.kleinbem.dev/api/v3/providers/oauth2/?client_id=cloudflare-access" | jq -c '{client: "cloudflare-access", secret_present: ((.results[0].client_secret // "") != "")}'


# --- GitHub provider inputs (sourced from sops) ---
# The GitHub App credentials (nix/shared.yaml) authenticate the github provider
# and go to CI repos as APP_*. ATTIC_PUSH_TOKEN falls back to orin-nano's
# attic_push_token when attic_ci_push_token is unset.
GH_APP_ID=$(echo "$SHARED_YAML" | yq '.github_app_id')
GH_APP_INSTALLATION_ID=$(echo "$SHARED_YAML" | yq '.github_app_installation_id')
GH_APP_ORG_INSTALLATION_ID=$(echo "$SHARED_YAML" | yq '.github_app_org_installation_id')
GH_APP_PRIVATE_KEY=$(echo "$SHARED_YAML" | yq '.github_app_private_key')
ATTIC_PUSH=$(echo "$DECRYPTED_YAML" | yq '.attic_ci_push_token')
[ "$ATTIC_PUSH" = "null" ] && ATTIC_PUSH=$(echo "$ORIN_YAML" | yq '.attic_push_token')
# attic_ci_pull_token becomes ATTIC_PULL_TOKEN (pull-only, for PR builds). Mint with
# `just nixos::attic-mint infra/terraform.yaml attic_ci_pull_token --sub github-ci-pull --pull system`.
ATTIC_PULL=$(echo "$DECRYPTED_YAML" | yq '.attic_ci_pull_token')
if [ "$ATTIC_PULL" = "null" ]; then
  echo -e "${RED}❌ attic_ci_pull_token missing in $TERRAFORM_FILE; mint it first (see above).${RESET}" >&2
  exit 1
fi
# Optional: write token for the kleinbem-nixpkgs-review Cachix cache.
CACHIX_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.cachix_auth_token')
# Optional: public cache S3 credentials (from r2-tokens/sync-secrets.sh) and the
# hand-made signing key.
PUBLIC_CACHE_KEY_ID=$(echo "$DECRYPTED_YAML" | yq '.public_cache_access_key_id')
PUBLIC_CACHE_SECRET=$(echo "$DECRYPTED_YAML" | yq '.public_cache_secret_access_key')
PUBLIC_CACHE_SIGNING_KEY=$(echo "$DECRYPTED_YAML" | yq '.public_cache_signing_key')
# Optional: the R2 budget watchdog's token (from r2-tokens/sync-secrets.sh).
R2_BUDGET_TOKEN=$(echo "$DECRYPTED_YAML" | yq '.r2_budget_token')
NETBIRD_KEY=$(echo "$SHARED_YAML" | yq '.netbird_setup_key')
NETBIRD_KEY_EPHEMERAL=$(echo "$DECRYPTED_YAML" | yq '.netbird_setup_key_ephemeral')
NTFY_DEPLOY_TOPIC=$(echo "$SHARED_YAML" | yq '.ntfy_deploy_topic')
# In nix/shared.yaml because hosts post alerts to it too and can't decrypt infra/*.
NTFY_ALERT_TOPIC=$(echo "$SHARED_YAML" | yq '.ntfy_alert_topic')
# CI's ntfy bearer token (NTFY_CI_TOKEN). Optional until ntfy.kleinbem.dev
# runs with auth (nix-presets ntfy.secretsFile); empty means "no header".
NTFY_CI_TOKEN=$(echo "$SHARED_YAML" | yq '.ntfy_ci_token')
[ "$NTFY_CI_TOKEN" = "null" ] && NTFY_CI_TOKEN=""
NTFY_CI_TOKEN=$(echo "$SHARED_YAML" | yq '.ntfy_ci_token')
[ "$NTFY_CI_TOKEN" = "null" ] && NTFY_CI_TOKEN=""

# --- Google Cloud (infra/google.tf) ---
# Hand-made bootstrap service-account key (base64 JSON), see infra/google.tf.
GOOGLE_SA_KEY=$(echo "$DECRYPTED_YAML" | yq '.google_service_account_key')
# healthchecks.io API key; healthchecks.tf requires it.
HEALTHCHECKS_API_KEY=$(echo "$DECRYPTED_YAML" | yq '.healthchecks_api_key')

# Normalise missing keys ("null") to empty strings
[ "$GH_APP_ID" = "null" ] && GH_APP_ID=""
[ "$GH_APP_INSTALLATION_ID" = "null" ] && GH_APP_INSTALLATION_ID=""
[ "$GH_APP_PRIVATE_KEY" = "null" ] && GH_APP_PRIVATE_KEY=""
[ "$ATTIC_PUSH" = "null" ] && ATTIC_PUSH=""
[ "$CACHIX_TOKEN" = "null" ] && CACHIX_TOKEN=""
[ "$PUBLIC_CACHE_KEY_ID" = "null" ] && PUBLIC_CACHE_KEY_ID=""
[ "$PUBLIC_CACHE_SECRET" = "null" ] && PUBLIC_CACHE_SECRET=""
[ "$PUBLIC_CACHE_SIGNING_KEY" = "null" ] && PUBLIC_CACHE_SIGNING_KEY=""
[ "$R2_BUDGET_TOKEN" = "null" ] && R2_BUDGET_TOKEN=""
[ "$NETBIRD_KEY" = "null" ] && NETBIRD_KEY=""
[ "$NETBIRD_KEY_EPHEMERAL" = "null" ] && NETBIRD_KEY_EPHEMERAL=""
[ "$NTFY_DEPLOY_TOPIC" = "null" ] && NTFY_DEPLOY_TOPIC=""
[ "$NTFY_ALERT_TOPIC" = "null" ] && NTFY_ALERT_TOPIC=""
[ "$GOOGLE_SA_KEY" = "null" ] && GOOGLE_SA_KEY=""
[ "$HEALTHCHECKS_API_KEY" = "null" ] && HEALTHCHECKS_API_KEY=""

# The github provider authenticates as the App, so all three are required:
# without them every github_* resource fails, and a refresh would error out
# halfway through an apply. Stop before touching anything.
if [ -z "$GH_APP_ID" ] || [ -z "$GH_APP_INSTALLATION_ID" ] || [ -z "$GH_APP_PRIVATE_KEY" ]; then
  echo -e "${RED}❌ github_app_id, github_app_installation_id and github_app_private_key must all be set in $SHARED_FILE — infra/main.tf's github provider authenticates with them (app_auth).${RESET}"
  exit 1
fi
# The `org` provider alias (kleinbem-dev) needs the App's installation id
# there too: install the App on the org (Settings → GitHub Apps) and store the
# id as github_app_org_installation_id.
[ "$GH_APP_ORG_INSTALLATION_ID" = "null" ] && GH_APP_ORG_INSTALLATION_ID=""
if [ -z "$GH_APP_ORG_INSTALLATION_ID" ]; then
  echo -e "${RED}❌ github_app_org_installation_id must be set in $SHARED_FILE — infra/main.tf's github.org provider (kleinbem-dev repos) authenticates with it.${RESET}"
  exit 1
fi

if [ -z "$GOOGLE_SA_KEY" ]; then
  echo -e "${YELLOW}⚠️  google_service_account_key not set in $TERRAFORM_FILE — infra/google.tf resources will fail to authenticate.${RESET}"
fi

export TF_VAR_github_app_id="$GH_APP_ID"
export TF_VAR_github_app_installation_id="$GH_APP_INSTALLATION_ID"
export TF_VAR_github_app_org_installation_id="$GH_APP_ORG_INSTALLATION_ID"
export TF_VAR_github_app_private_key="$GH_APP_PRIVATE_KEY"
export TF_VAR_attic_push_token="$ATTIC_PUSH"
export TF_VAR_attic_pull_token="$ATTIC_PULL"
export TF_VAR_cachix_auth_token="$CACHIX_TOKEN"
export TF_VAR_public_cache_access_key_id="$PUBLIC_CACHE_KEY_ID"
export TF_VAR_public_cache_secret_access_key="$PUBLIC_CACHE_SECRET"
export TF_VAR_public_cache_signing_key="$PUBLIC_CACHE_SIGNING_KEY"
export TF_VAR_r2_budget_token="$R2_BUDGET_TOKEN"
export TF_VAR_netbird_setup_key="$NETBIRD_KEY"
export TF_VAR_netbird_setup_key_ephemeral="$NETBIRD_KEY_EPHEMERAL"
export TF_VAR_ntfy_deploy_topic="$NTFY_DEPLOY_TOPIC"
export TF_VAR_ntfy_alert_topic="$NTFY_ALERT_TOPIC"
export TF_VAR_google_service_account_key="$GOOGLE_SA_KEY"
export TF_VAR_healthchecks_api_key="$HEALTHCHECKS_API_KEY"

# 2. OpenTofu Init & Plan/Apply
echo -e "\n${BOLD}[2/4] Initializing OpenTofu...${RESET}"

# --- R2 state backend config (see infra/backend.tf) ---
# R2 keys from sops, falling back to AWS_* env. They go into the backend-config
# file below, never exported as AWS_*, so the aws provider can't pick them up.
R2_KEY_ID=$(echo "$DECRYPTED_YAML" | yq '.r2_state_access_key_id')
R2_KEY_SECRET=$(echo "$DECRYPTED_YAML" | yq '.r2_state_secret_access_key')
[ "$R2_KEY_ID" = "null" ] && R2_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
[ "$R2_KEY_SECRET" = "null" ] && R2_KEY_SECRET="${AWS_SECRET_ACCESS_KEY:-}"

export TF_VAR_r2_state_access_key_id="$R2_KEY_ID"
export TF_VAR_r2_state_secret_access_key="$R2_KEY_SECRET"
export TF_VAR_authentik_api_token="$AUTHENTIK_API_TOKEN"
export TF_VAR_kleinbem_auth_google_client_id="$GOOGLE_CLIENT_ID"
export TF_VAR_kleinbem_auth_google_client_secret="$GOOGLE_CLIENT_SECRET"

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

cd "$(dirname "${BASH_SOURCE[0]}")/../infra"
# R2 keys stay on disk only for this run: the backend config is on tmpfs, and
# the copy `tofu init` caches in .terraform/terraform.tfstate is blanked on exit.
rm -f .r2-backend.hcl # older runs left it here
BACKEND_CFG=$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}" r2-backend.XXXXXX.hcl)
cleanup_backend() {
  rm -f "$BACKEND_CFG"
  if [ -f .terraform/terraform.tfstate ]; then
    jq '.backend.config.access_key = null | .backend.config.secret_key = null' \
      .terraform/terraform.tfstate >.terraform/terraform.tfstate.tmp &&
      mv .terraform/terraform.tfstate.tmp .terraform/terraform.tfstate
  fi
}
trap cleanup_backend EXIT
cat >"$BACKEND_CFG" <<EOF
endpoints  = { s3 = "https://${ACCOUNT_ID}.r2.cloudflarestorage.com" }
access_key = "${R2_KEY_ID}"
secret_key = "${R2_KEY_SECRET}"
EOF

if [ "$MODE" = "migrate-state" ]; then
  echo -e "${YELLOW}Migrating local terraform.tfstate into the R2 backend (kleinbem-tofu-state/infra.tfstate)...${RESET}"
  echo -e "${YELLOW}Local tfstate files stay behind, gitignored, as a fallback copy.${RESET}"
  tofu init -backend-config="$BACKEND_CFG" -migrate-state -force-copy
  echo -e "\n${BOLD}${GREEN}✅ State migrated to R2. Verify with: $0 --plan-only (expect no changes).${RESET}"
  exit 0
fi

tofu init -input=false -reconfigure -backend-config="$BACKEND_CFG"

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

if [ "$MODE" = "state-rm" ]; then
  if [ ${#PASSTHROUGH[@]} -eq 0 ]; then
    echo -e "${RED}❌ Missing resource address for --state-rm.${RESET}"
    exit 1
  fi
  for res in "${PASSTHROUGH[@]}"; do
    echo -e "${YELLOW}Removing ${res} from OpenTofu state...${RESET}"
    tofu state rm "$res"
  done
  echo -e "\n${BOLD}${GREEN}✅ Removed from state.${RESET}"
  exit 0
fi

if [ "$MODE" = "exec" ]; then
  if [ ${#PASSTHROUGH[@]} -eq 0 ]; then
    echo -e "${RED}❌ Missing tofu arguments for --exec.${RESET}"
    exit 1
  fi
  echo -e "\n${BOLD}Executing: tofu ${PASSTHROUGH[*]}${RESET}"
  tofu "${PASSTHROUGH[@]}"
  exit 0
fi

echo -e "\n${BOLD}Applying OpenTofu plan...${RESET}"
# Refuses planned deletes/replacements unless ALLOW_DESTROY=1.
if [ ${#PASSTHROUGH[@]} -gt 0 ]; then
  echo -e "${YELLOW}Passthrough args: ${PASSTHROUGH[*]}${RESET}"
  "$GUARDED_APPLY" "${PASSTHROUGH[@]}"
else
  "$GUARDED_APPLY" -auto-approve
fi

# 3. Capture Output
# Every capture tolerates a missing output, so a -target apply still writes
# back whatever it did produce.
echo -e "\n${BOLD}[3/4] Capturing outputs...${RESET}"
TUNNEL_ID=$(tofu output -raw tunnel_id 2>/dev/null || echo "")
GEMINI_API_KEY_JUAN=$(tofu output -raw juan_gemini_api_key 2>/dev/null || echo "")
OIDC_SECRETS_JSON=$(tofu output -json oidc_client_secrets 2>/dev/null || echo "{}")
cd ..

if [ -z "$TUNNEL_ID" ]; then
  echo -e "${YELLOW}⚠️  tunnel_id not present in state (narrow apply that didn't include it?) — skipping tunnel-id write-back.${RESET}"
else
  echo -e "🟢 Tunnel ID: ${BOLD}$TUNNEL_ID${RESET}"

  # core-pi's secrets.nix reads cloudflare_tunnel_id from this file.
  CURRENT_TUNNEL_ID=$(echo "$COREPI_YAML" | yq '.cloudflare_tunnel_id')
  if [ "$CURRENT_TUNNEL_ID" != "$TUNNEL_ID" ]; then
    echo -e "Updating cloudflare_tunnel_id in nix/per-host/core-pi.yaml..."
    sops --set "[\"cloudflare_tunnel_id\"] \"$TUNNEL_ID\"" "$COREPI_FILE"
    echo -e "🟢 Updated cloudflare_tunnel_id in nix/per-host/core-pi.yaml"
  fi
fi

# Write juan's Gemini key into his persona file (gemini_api_key). Repeat this
# block for each persona that gets a google_apikeys_key.
if [ -n "$GEMINI_API_KEY_JUAN" ]; then
  JUAN_YAML="$SECRETS_ROOT/personas/juan-gonzalez.yaml"
  GEMINI_WORK="$(mktemp -d /dev/shm/tf-apply-gemini-XXXXXX)"
  trap 'cleanup_backend; find "$GEMINI_WORK" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "$GEMINI_WORK"' EXIT
  sops -d "$JUAN_YAML" >"$GEMINI_WORK/juan.yaml"
  # Only re-encrypt on change: sops rewrites every ciphertext line, which would
  # dirty kleinbem-secrets on every apply.
  if [ "$(yq '.gemini_api_key' "$GEMINI_WORK/juan.yaml")" = "$GEMINI_API_KEY_JUAN" ]; then
    echo -e "🟢 juan's Gemini API key unchanged — kleinbem-secrets left untouched"
  else
    printf '%s' "$GEMINI_API_KEY_JUAN" >"$GEMINI_WORK/gemini_api_key.txt"
    GEMINI_KEY_PATH="$GEMINI_WORK/gemini_api_key.txt" yq -i \
      '.gemini_api_key = load_str(strenv(GEMINI_KEY_PATH))' "$GEMINI_WORK/juan.yaml"
    sops --config "$SECRETS_ROOT/.sops.yaml" --filename-override "$JUAN_YAML" \
      -e "$GEMINI_WORK/juan.yaml" >"$GEMINI_WORK/juan-enc.yaml"
    mv "$GEMINI_WORK/juan-enc.yaml" "$JUAN_YAML"
    echo -e "🟢 Wrote juan's Gemini API key to kleinbem-secrets/personas/juan-gonzalez.yaml"
  fi
fi

# Auto-sync Authentik OIDC client secrets to kleinbem-secrets/nix/per-container/<app>.yaml
if [ -n "$OIDC_SECRETS_JSON" ] && [ "$OIDC_SECRETS_JSON" != "{}" ] && [ "$OIDC_SECRETS_JSON" != "null" ]; then
  echo -e "\n${BOLD}Syncing Authentik OIDC client secrets to kleinbem-secrets...${RESET}"
  for app in $(echo "$OIDC_SECRETS_JSON" | jq -r 'keys[]'); do
    app_secret=$(echo "$OIDC_SECRETS_JSON" | jq -r --arg a "$app" '.[$a]')
    if [ -z "$app_secret" ] || [ "$app_secret" = "null" ]; then
      continue
    fi

    # Container name in per-container: grafana lives in monitoring.yaml, others live in <app>.yaml
    container_name="$app"
    [ "$app" = "grafana" ] && container_name="monitoring"

    APP_YAML="$SECRETS_ROOT/nix/per-container/${container_name}.yaml"
    key_name="${container_name//-/_}_oauth_client_secret"
    [ "$app" = "grafana" ] && key_name="monitoring_grafana_oauth_client_secret"

    if [ ! -f "$APP_YAML" ]; then
      mkdir -p "$(dirname "$APP_YAML")"
      echo "${key_name}: ${app_secret}" > "$APP_YAML"
      sops --config "$SECRETS_ROOT/.sops.yaml" -e -i "$APP_YAML"
      echo -e "🟢 Initialized and encrypted OIDC client secret in nix/per-container/${container_name}.yaml"
    else
      current_val=$(sops -d "$APP_YAML" 2>/dev/null | yq -r ".${key_name}" 2>/dev/null || echo "")
      if [ "$current_val" != "$app_secret" ]; then
        sops --set "[\"${key_name}\"] \"$app_secret\"" "$APP_YAML"
        echo -e "🟢 Updated ${app}'s OIDC client secret in nix/per-container/${container_name}.yaml"
      else
        echo -e "🟢 ${app}'s OIDC client secret unchanged in kleinbem-secrets"
      fi
    fi
  done
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
