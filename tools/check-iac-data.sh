#!/usr/bin/env bash
# Fails if infra/personas.json or infra/inventory.json drifted from nix-config.
# Fix with nix/tools/gen-iac-data.sh.
# Usage: check-iac-data.sh [FILE...]   (default: personas.json inventory.json;
# CI passes inventory.json only, since it has no contact file for personas)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
INFRA="$(dirname "$SCRIPT_DIR")/infra"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

IAC_DATA_SKIP_FLAKE=1 "$SCRIPT_DIR/gen-iac-data.sh" "$TMP" >/dev/null

errors=0
FILES=("$@")
[[ ${#FILES[@]} -gt 0 ]] || FILES=(personas.json inventory.json)
for f in "${FILES[@]}"; do
  if [[ ! -f "$INFRA/$f" ]]; then
    echo "❌ missing: infra/$f — run: nix/tools/gen-iac-data.sh"
    errors=$((errors + 1))
    continue
  fi
  if diff -u <(jq -S . "$INFRA/$f") <(jq -S . "$TMP/$f") >/dev/null 2>&1; then
    echo "✅ in sync: infra/$f"
  else
    echo "⚠️  DRIFTED: infra/$f"
    diff -u <(jq -S . "$INFRA/$f") <(jq -S . "$TMP/$f") | head -40 || true
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo
  echo "❌ $errors file(s) drifted from nix-config. Regenerate: nix/tools/gen-iac-data.sh"
  exit 1
fi
