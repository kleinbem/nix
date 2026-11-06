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

FILES=("$@")
[[ "${#FILES[@]}" -gt 0 ]] || FILES=(personas.json inventory.json)
for f in "${FILES[@]}"; do
  case $f in
  personas.json | inventory.json) ;;
  *)
    echo "❌ $f isn't checked here (only personas.json, inventory.json)" >&2
    exit 2
    ;;
  esac
done

IAC_DATA_SKIP_FLAKE=1 "$SCRIPT_DIR/gen-iac-data.sh" "$TMP" >/dev/null

errors=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$INFRA/$f" ]]; then
    echo "❌ missing: infra/$f — run: nix/tools/gen-iac-data.sh"
    errors=$((errors + 1))
    continue
  fi
  # Normalise into files first, so invalid JSON fails here under set -e
  # instead of two empty outputs comparing as in sync.
  jq -S . "$INFRA/$f" >"$TMP/committed-$f"
  jq -S . "$TMP/$f" >"$TMP/generated-$f"
  if diff -q "$TMP/committed-$f" "$TMP/generated-$f" >/dev/null; then
    echo "✅ in sync: infra/$f"
  else
    echo "⚠️  DRIFTED: infra/$f"
    diff -u "$TMP/committed-$f" "$TMP/generated-$f" | head -40 || true
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo
  echo "❌ $errors file(s) drifted from nix-config. Regenerate: nix/tools/gen-iac-data.sh"
  exit 1
fi
