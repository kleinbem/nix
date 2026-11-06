#!/usr/bin/env bash
# Source this (`. ./state-env.sh`) before any tofu command in this root (two
# YubiKey touches). Writes .r2-backend.hcl and exports TF_ENCRYPTION and
# TF_VAR_netbird_api_token. No AWS_* env: the main root's aws provider would read it.
# No `set -euo pipefail`: sourced, it would stay on in the caller's shell. The
# checks below catch every missing value instead.

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cloudflare_account_id comes from core-pi's file (it owns the Tunnel); the
# rest from infra/terraform.yaml.
_yaml="$(sops -d "${_here}/../../../kleinbem-secrets/infra/terraform.yaml")"
_corepi_yaml="$(sops -d "${_here}/../../../kleinbem-secrets/nix/per-host/core-pi.yaml")"

_account="$(echo "$_corepi_yaml" | yq '.cloudflare_account_id')"
_key_id="$(echo "$_yaml" | yq '.r2_state_access_key_id')"
_key_secret="$(echo "$_yaml" | yq '.r2_state_secret_access_key')"
_pass="$(echo "$_yaml" | yq '.tofu_state_passphrase')"
_token="$(echo "$_yaml" | yq '.netbird_api_token')"

for _v in _account _key_id _key_secret _pass _token; do
  if [ -z "${!_v}" ] || [ "${!_v}" = "null" ]; then
    echo "❌ ${_v#_} missing — need cloudflare_account_id in kleinbem-secrets/nix/per-host/core-pi.yaml, and r2_state_access_key_id/r2_state_secret_access_key/tofu_state_passphrase/netbird_api_token in kleinbem-secrets/infra/terraform.yaml" >&2
    # shellcheck disable=SC2317  # exit is the fallback when executed (not sourced)
    return 1 2>/dev/null || exit 1
  fi
done

# The passphrase goes into an HCL string unescaped; escaping would change the
# derived key for an existing state, so refuse characters HCL would interpret.
case "$_pass" in
  *\"* | *\\* | *\$\{* | *%\{*)
    echo "❌ tofu_state_passphrase contains \", \\, \${ or %{, which TF_ENCRYPTION can't carry verbatim" >&2
    # shellcheck disable=SC2317  # exit is the fallback when executed (not sourced)
    return 1 2>/dev/null || exit 1
    ;;
esac

export TF_ENCRYPTION="key_provider \"pbkdf2\" \"state_key\" { passphrase = \"${_pass}\" }"
export TF_VAR_netbird_api_token="${_token}"

# Subshell: the umask must not leak into the caller.
(
  umask 077
  cat >"${_here}/.r2-backend.hcl" <<EOF
endpoints  = { s3 = "https://${_account}.r2.cloudflarestorage.com" }
access_key = "${_key_id}"
secret_key = "${_key_secret}"
EOF
)

unset _yaml _corepi_yaml _account _key_id _key_secret _pass _token _v _here
