#!/usr/bin/env bash
# Exports personas → infra/personas.json so OpenTofu consumes the
# same source of truth as Nix.
#
# Merges the PUBLIC layer (nix-config/personas.nix — roles/auth) with
# the PRIVATE contact layer (kleinbem-secrets/personas/contact.nix — PII)
# into a single per-persona attrset. contact.nix is plain Nix (reverted
# from sops 2026-08-09 — full-name/email become public the moment a
# persona commits anything, so encrypting it at rest never bought real
# confidentiality), imported directly, no decrypt step. If
# kleinbem-secrets isn't on disk (e.g. running from a public clone),
# public-only data is exported and PII fields are absent.
#
# Idempotent — overwrites the JSON each run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
META_ROOT="$(dirname "$SCRIPT_DIR")"
# nix-config/kleinbem-secrets are flat siblings of nix/, not nested under it.
WORKSPACE_ROOT="$(dirname "$META_ROOT")"
PERSONAS_NIX="$WORKSPACE_ROOT/nix-config/personas.nix"
CONTACT_FILE="$WORKSPACE_ROOT/kleinbem-secrets/personas/contact.nix"
PERSONAS_JSON="$META_ROOT/infra/personas.json"

if [[ ! -f $PERSONAS_NIX ]]; then
  echo "❌ Missing $PERSONAS_NIX" >&2
  exit 1
fi

if [[ -f $CONTACT_FILE ]]; then
  echo "📤 Exporting personas.nix ⊕ personas/contact.nix → $(basename "$PERSONAS_JSON")..."
  nix eval --json --impure --expr "
    let
      pub = import $PERSONAS_NIX;
      contact = import $CONTACT_FILE;
    in
    builtins.mapAttrs (name: p: p // (contact.\${name} or {})) pub
  " >"$PERSONAS_JSON"
else
  echo "⚠️  kleinbem-secrets/personas/contact.nix not found — exporting PUBLIC-ONLY data" >&2
  nix eval --json --file "$PERSONAS_NIX" >"$PERSONAS_JSON"
fi

echo "✅ Wrote $(jq 'keys | length' <"$PERSONAS_JSON") personas to $PERSONAS_JSON"
echo "   $(jq -r 'keys | join(", ")' <"$PERSONAS_JSON")"
