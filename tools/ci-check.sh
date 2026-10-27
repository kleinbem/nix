#!/usr/bin/env bash
# Secret-free checks for the infra/ roots and tools/, run by CI
# (.github/workflows/ci.yaml) and runnable locally: tools/ci-check.sh
#
# Needs tofu, just, yq and shellcheck on PATH. Uses a dummy state
# passphrase and a stub sops, never real secrets or real state.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ROOTS=(infra infra/garage infra/netbird infra/r2-tokens)
DUMMY_PASSPHRASE="ci-dummy-passphrase-not-a-secret"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== tofu fmt"
tofu fmt -check -recursive -diff infra

echo "== tofu validate"
for root in "${ROOTS[@]}"; do
  echo "-- $root"
  (
    cd "$root"
    export TF_DATA_DIR="$TMP/tf-data/${root//\//_}"
    export TF_ENCRYPTION="key_provider \"pbkdf2\" \"state_key\" { passphrase = \"$DUMMY_PASSPHRASE\" }"
    tofu init -backend=false -input=false >/dev/null
    tofu validate
  )
done

# The garage root keeps local state, so its `just init` runs without any
# backend credentials. A stub sops stands in for kleinbem-secrets: this
# catches recipes that forget to pass the state passphrase to tofu.
echo "== garage: just init with a stub sops"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/sops" <<STUB
#!/bin/sh
printf 'tofu_state_passphrase: $DUMMY_PASSPHRASE\ngarage_admin_token: dummy\n'
STUB
chmod +x "$TMP/bin/sops"
(
  cd infra/garage
  PATH="$TMP/bin:$PATH" TF_DATA_DIR="$TMP/tf-data/garage-recipe" just init >/dev/null
)

echo "== Justfiles parse"
for root in "${ROOTS[@]}"; do
  [ -f "$root/Justfile" ] && just --justfile "$root/Justfile" --summary >/dev/null
done

echo "== shellcheck"
shellcheck -S warning tools/*.sh infra/*/*.sh

echo "All checks passed."
