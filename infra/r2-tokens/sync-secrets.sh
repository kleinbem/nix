#!/usr/bin/env bash
# Write each host's rclone config (tofu output backup_r2_rclone_configs) into
# kleinbem-secrets/nix/per-host/<host>.yaml as backup_r2_rclone_config — read
# by nix-config/modules/nixos/backup.nix. Run after `tofu apply` in the same
# state-env session (the Justfile's `apply` does).
#
# Values go in via stdin (never argv). --idempotent leaves an unchanged file
# byte-identical, so re-runs don't churn ciphertext. A host without a
# per-host file yet (nasbook) gets one created — encrypting needs only the
# public recipients from .sops.yaml. Updating an existing file decrypts its
# data key: expect a YubiKey touch per host.
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_ROOT="$(cd "${_here}/../../../kleinbem-secrets" && pwd)"

CONFIGS=$(cd "$_here" && tofu output -json backup_r2_rclone_configs)
if [ -z "$CONFIGS" ] || [ "$CONFIGS" = "{}" ] || [ "$CONFIGS" = "null" ]; then
  echo "⚠️  no backup_r2_rclone_configs output — nothing to sync" >&2
  exit 0
fi

for host in $(echo "$CONFIGS" | jq -r 'keys[]'); do
  HOST_YAML="$SECRETS_ROOT/nix/per-host/${host}.yaml"
  if [ ! -f "$HOST_YAML" ]; then
    work="$(mktemp -d /dev/shm/r2-tokens-XXXXXX)"
    echo "$CONFIGS" | jq -r --arg h "$host" '{backup_r2_rclone_config: .[$h]}' | yq -P >"$work/plain.yaml"
    sops --config "$SECRETS_ROOT/.sops.yaml" --filename-override "$HOST_YAML" \
      -e "$work/plain.yaml" >"$HOST_YAML"
    shred -u "$work/plain.yaml"
    rmdir "$work"
    echo "🟢 created nix/per-host/${host}.yaml with backup_r2_rclone_config"
  else
    echo "$CONFIGS" | jq -c --arg h "$host" '.[$h]' |
      sops set --idempotent --value-stdin "$HOST_YAML" '["backup_r2_rclone_config"]'
    echo "🟢 backup_r2_rclone_config in sync for ${host}"
  fi
done

echo
echo "Next: review + push kleinbem-secrets (jj st there), then bump it in nix-config."
