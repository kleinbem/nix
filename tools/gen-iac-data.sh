#!/usr/bin/env bash
# Generates the JSON bridge files the nix/infra OpenTofu roots consume, from
# repo-canonical Nix data:
#
#   nix-config/personas.nix ⊕ kleinbem-secrets/personas/contact.nix
#   nix-config/inventory.nix  (its `meshGroups` attr)
#            │
#            ▼  projection logic: nix-config/iac/data.nix
#   infra/personas.json    → personas.tf, cloudflare-dns.tf
#   infra/inventory.json   → netbird/{inventory,groups}.tf
#
# Idempotent — overwrites both files each run. Byte-identical to what
# `nix build nix-config#iac-data` and the `iac-data` flake check emit (all
# three call iac/data.nix and pipe through `jq -S`). Replaces the old
# export-personas.sh (personas only) plus the hand-maintained peer-list
# duplicates in netbird/{groups,peers}.tf.
#
# Usage: gen-iac-data.sh [DEST_DIR]   (default: nix/infra)
#   check-iac-data.sh calls it with a tempdir to diff against the committed copy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
META_ROOT="$(dirname "$SCRIPT_DIR")"          # .../nix
WORKSPACE_ROOT="$(dirname "$META_ROOT")"      # .../<workspace root>
NIX_CONFIG="$WORKSPACE_ROOT/nix-config"
CONTACT_FILE="$WORKSPACE_ROOT/kleinbem-secrets/personas/contact.nix"
DATA_NIX="$NIX_CONFIG/iac/data.nix"
DEST="${1:-$META_ROOT/infra}"

[[ -f $DATA_NIX ]] || {
  echo "❌ $DATA_NIX not found — is nix-config checked out next to nix/?" >&2
  exit 1
}

if [[ -f $CONTACT_FILE ]]; then
  contact_expr="import $CONTACT_FILE"
else
  echo "⚠️  $CONTACT_FILE not found — personas.json will omit PII fields (public-only)" >&2
  contact_expr="{}"
fi

emit() { # <data.nix attr> <dest file>
  nix eval --impure --raw --expr "
    let
      lib = (import <nixpkgs> { }).lib;
      data = import $DATA_NIX {
        inherit lib;
        contact = $contact_expr;
      };
    in builtins.toJSON data.$1
  " | jq -S . >"$2"
}

emit personasJson "$DEST/personas.json"
emit inventoryJson "$DEST/inventory.json"

# heartbeats.json and backup-hosts.json need the *evaluated* host configs
# (my.heartbeat.checks, my.backup.items), so they come from nix-config's flake
# outputs rather than iac/data.nix. Written via a temp file so a failed eval
# never truncates the committed copy.
emit_flake() { # <nix-config flake attr> <dest file>
  local tmp
  tmp=$(mktemp)
  if nix eval --json "$NIX_CONFIG#$1" 2>/dev/null | jq -S . >"$tmp" && [[ -s $tmp ]]; then
    mv "$tmp" "$2"
    echo "✅ wrote $2"
  else
    rm -f "$tmp"
    echo "⚠️  nix-config#$1 eval failed — keeping the committed $(basename "$2")" >&2
  fi
}

echo "✅ wrote $DEST/personas.json + $DEST/inventory.json"
emit_flake heartbeats "$DEST/heartbeats.json"
emit_flake backupHosts "$DEST/backup-hosts.json"
