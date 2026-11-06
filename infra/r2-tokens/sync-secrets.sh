#!/usr/bin/env bash
# Copy this root's outputs into kleinbem-secrets. Run after apply in a state-env
# session (`just apply` / `just sync` do). Values go in via stdin, never argv.
# A missing per-host file is created from .sops.yaml's public recipients;
# updating an existing one needs a YubiKey touch per file.
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_ROOT="$(cd "${_here}/../../../kleinbem-secrets" && pwd)"

CONFIGS=$(cd "$_here" && tofu output -json backup_r2_rclone_configs)
# No hosts left still syncs the shared credentials below.
if [ -z "$CONFIGS" ] || [ "$CONFIGS" = "null" ]; then
  echo "⚠️  no backup_r2_rclone_configs output — skipped the per-host configs" >&2
  CONFIGS="{}"
fi

for host in $(echo "$CONFIGS" | jq -r 'keys[]'); do
  HOST_YAML="$SECRETS_ROOT/nix/per-host/${host}.yaml"
  if [ ! -f "$HOST_YAML" ]; then
    work="$(mktemp -d /dev/shm/r2-tokens-XXXXXX)"
    echo "$CONFIGS" | jq -r --arg h "$host" '{backup_r2_rclone_config: .[$h]}' | yq -P >"$work/plain.yaml"
    # --filename-override only picks the .sops.yaml rule; HOST_YAML doesn't exist yet.
    # Encrypt to a temp file first: a failed sops must not leave an empty
    # HOST_YAML, which the next run would take for an existing one.
    # The temp file sits next to HOST_YAML, so the mv is an atomic rename.
    enc="$(mktemp "${HOST_YAML}.XXXXXX")"
    # shellcheck disable=SC2094
    if ! sops --config "$SECRETS_ROOT/.sops.yaml" --filename-override "$HOST_YAML" \
      -e "$work/plain.yaml" >"$enc"; then
      shred -u "$work/plain.yaml"
      rmdir "$work"
      rm -f "$enc"
      exit 1
    fi
    shred -u "$work/plain.yaml"
    rmdir "$work"
    mv "$enc" "$HOST_YAML"
    echo "🟢 created nix/per-host/${host}.yaml with backup_r2_rclone_config"
  else
    echo "$CONFIGS" | jq -c --arg h "$host" '.[$h]' |
      sops set --idempotent --value-stdin "$HOST_YAML" '["backup_r2_rclone_config"]'
    echo "🟢 backup_r2_rclone_config in sync for ${host}"
  fi
done

# Caddy's DNS-01 token (acme-dns.tf) → core-pi, read by nix-config
# hosts/core-pi/secrets.nix into the caddy container's env file.
ACME_TOKEN=$(cd "$_here" && tofu output -raw caddy_acme_dns_token 2>/dev/null || true)
if [ -n "$ACME_TOKEN" ]; then
  printf '%s' "$ACME_TOKEN" | jq -Rs . |
    sops set --idempotent --value-stdin "$SECRETS_ROOT/nix/per-host/core-pi.yaml" '["caddy_acme_cloudflare_token"]'
  echo "🟢 caddy_acme_cloudflare_token in sync for core-pi"
else
  echo "⚠️  no caddy_acme_dns_token output — skipped core-pi's caddy_acme_cloudflare_token" >&2
fi
unset ACME_TOKEN

# CI credentials for the public cache (public-cache.tf) → infra/terraform.yaml,
# read by tools/tf-apply.sh for the main root.
CACHE_CI=$(cd "$_here" && tofu output -json public_cache_ci 2>/dev/null || true)
if [ -n "$CACHE_CI" ] && [ "$CACHE_CI" != "null" ]; then
  for key in access_key_id secret_access_key; do
    echo "$CACHE_CI" | jq -c --arg k "$key" '.[$k]' |
      sops set --idempotent --value-stdin "$SECRETS_ROOT/infra/terraform.yaml" "[\"public_cache_$key\"]"
  done
  echo "🟢 public_cache_{access_key_id,secret_access_key} in sync in infra/terraform.yaml"
else
  echo "⚠️  no public_cache_ci output — skipped the public cache's CI credentials" >&2
fi
unset CACHE_CI

# The r2-budget watchdog's token (r2-budget.tf) → infra/terraform.yaml.
BUDGET_TOKEN=$(cd "$_here" && tofu output -raw r2_budget_token 2>/dev/null || true)
if [ -n "$BUDGET_TOKEN" ]; then
  printf '%s' "$BUDGET_TOKEN" | jq -Rs . |
    sops set --idempotent --value-stdin "$SECRETS_ROOT/infra/terraform.yaml" '["r2_budget_token"]'
  echo "🟢 r2_budget_token in sync in infra/terraform.yaml"
else
  echo "⚠️  no r2_budget_token output — skipped the budget watchdog's token" >&2
fi
unset BUDGET_TOKEN

echo
echo "Next: review + push kleinbem-secrets (jj st there), then bump it in nix-config."
