#!/usr/bin/env bash
# Source this (`. ./state-env.sh`) before any tofu command in this root (two
# YubiKey touches). Writes .r2-backend.hcl and exports TF_ENCRYPTION and the
# TF_VARs. The zone id is looked up with the main root's token, since the minter
# can't read zones. No AWS_* env: the main root's aws provider would read it.
# No `set -euo pipefail`: sourced, it would stay on in the caller's shell. The
# checks below catch every missing value instead.

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_yaml="$(sops -d "${_here}/../../../kleinbem-secrets/infra/terraform.yaml")"
_corepi_yaml="$(sops -d "${_here}/../../../kleinbem-secrets/nix/per-host/core-pi.yaml")"

_account="$(echo "$_corepi_yaml" | yq '.cloudflare_account_id')"
_key_id="$(echo "$_yaml" | yq '.r2_state_access_key_id')"
_key_secret="$(echo "$_yaml" | yq '.r2_state_secret_access_key')"
_pass="$(echo "$_yaml" | yq '.tofu_state_passphrase')"
_minter="$(echo "$_yaml" | yq '.cloudflare_token_minter_token')"
_cf_read="$(echo "$_yaml" | yq '.cloudflare_api_token')"
_zone="$(curl -fsS -H "Authorization: Bearer ${_cf_read}" \
  "https://api.cloudflare.com/client/v4/zones?name=kleinbem.dev" | jq -r '.result[0].id // empty')" || _zone=""

for _v in _account _key_id _key_secret _pass _minter _zone; do
  if [ -z "${!_v}" ] || [ "${!_v}" = "null" ]; then
    echo "❌ ${_v#_} missing — need cloudflare_account_id in kleinbem-secrets/nix/per-host/core-pi.yaml, and r2_state_access_key_id/r2_state_secret_access_key/tofu_state_passphrase/cloudflare_token_minter_token/cloudflare_api_token in kleinbem-secrets/infra/terraform.yaml (zone = kleinbem.dev zone id lookup)" >&2
    # shellcheck disable=SC2317  # exit runs when executed; upstream: koalaman/shellcheck#2620
    return 1 2>/dev/null || exit 1
  fi
done

# The passphrase goes into an HCL string unescaped; escaping would change the
# derived key for an existing state, so refuse characters HCL would interpret.
case "$_pass" in
  *\"* | *\\* | *\$\{* | *%\{*)
    echo "❌ tofu_state_passphrase contains \", \\, \${ or %{, which TF_ENCRYPTION can't carry verbatim" >&2
    # shellcheck disable=SC2317  # exit runs when executed; upstream: koalaman/shellcheck#2620
    return 1 2>/dev/null || exit 1
    ;;
esac

export TF_ENCRYPTION="key_provider \"pbkdf2\" \"state_key\" { passphrase = \"${_pass}\" }"
export TF_VAR_cloudflare_token_minter_token="${_minter}"
export TF_VAR_cloudflare_account_id="${_account}"
export TF_VAR_cloudflare_zone_id="${_zone}"

# Subshell: the umask must not leak into the caller.
(
  umask 077
  cat >"${_here}/.r2-backend.hcl" <<EOT
endpoints  = { s3 = "https://${_account}.r2.cloudflarestorage.com" }
access_key = "${_key_id}"
secret_key = "${_key_secret}"
EOT
) || {
  echo "❌ couldn't write ${_here}/.r2-backend.hcl" >&2
  # shellcheck disable=SC2317  # exit runs when executed; upstream: koalaman/shellcheck#2620
  return 1 2>/dev/null || exit 1
}

unset _yaml _corepi_yaml _account _key_id _key_secret _pass _minter _cf_read _zone _v _here
