#!/usr/bin/env bash
# Exports nix-config/personas.nix → terraform/personas.json so the Terraform
# config can consume the same source of truth as everything else.
#
# Run from anywhere; resolves paths relative to the script's own location.
# Idempotent — overwrites the JSON each run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
META_ROOT="$(dirname "$SCRIPT_DIR")"
PERSONAS_NIX="$META_ROOT/nix-config/personas.nix"
PERSONAS_JSON="$META_ROOT/terraform/personas.json"

if [[ ! -f "$PERSONAS_NIX" ]]; then
  echo "❌ Missing $PERSONAS_NIX" >&2
  exit 1
fi

echo "📤 Exporting personas.nix → $(basename "$PERSONAS_JSON")..."
nix eval --json --file "$PERSONAS_NIX" > "$PERSONAS_JSON"

echo "✅ Wrote $(jq 'keys | length' < "$PERSONAS_JSON") personas to $PERSONAS_JSON"
echo "   $(jq -r 'keys | join(", ")' < "$PERSONAS_JSON")"
