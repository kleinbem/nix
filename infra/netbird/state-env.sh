#!/usr/bin/env bash
# Source this (`. ./state-env.sh`) before any tofu invocation in this root.
# Decrypts sops ONCE (one YubiKey touch) and prepares everything state ops need:
#   - .r2-backend.hcl (R2 endpoint + access key) for `tofu init -backend-config`
#   - TF_ENCRYPTION   (client-side state encryption passphrase, encryption.tf)
#   - TF_VAR_netbird_api_token (provider auth)
# Credentials go in the generated file / env for THIS process only — never
# AWS_* env (collides with real-AWS provider auth elsewhere in the workspace).
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_yaml="$(sops -d "${_here}/../../nix-secrets/secrets.yaml")"

_account="$(echo "$_yaml" | yq '.cloudflare_account_id')"
_key_id="$(echo "$_yaml" | yq '.r2_state_access_key_id')"
_key_secret="$(echo "$_yaml" | yq '.r2_state_secret_access_key')"
_pass="$(echo "$_yaml" | yq '.tofu_state_passphrase')"
_token="$(echo "$_yaml" | yq '.netbird_api_token')"

for _v in _account _key_id _key_secret _pass _token; do
  if [ -z "${!_v}" ] || [ "${!_v}" = "null" ]; then
    echo "❌ ${_v#_} missing in nix-secrets/secrets.yaml (need cloudflare_account_id, r2_state_access_key_id, r2_state_secret_access_key, tofu_state_passphrase, netbird_api_token)" >&2
    # shellcheck disable=SC2317  # exit is the fallback when executed (not sourced)
    return 1 2>/dev/null || exit 1
  fi
done

export TF_ENCRYPTION="key_provider \"pbkdf2\" \"state_key\" { passphrase = \"${_pass}\" }"
export TF_VAR_netbird_api_token="${_token}"

umask 077
cat >"${_here}/.r2-backend.hcl" <<EOF
endpoints  = { s3 = "https://${_account}.r2.cloudflarestorage.com" }
access_key = "${_key_id}"
secret_key = "${_key_secret}"
EOF

unset _yaml _account _key_id _key_secret _pass _token _v _here
