#!/usr/bin/env bash
# Verifies that scripts mirrored across submodule boundaries have not drifted.
#
# Each pair is (source, mirror). Compare ignoring the marker comment lines
# (those differ on purpose between the two locations).

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PAIRS=(
  "nix-presets/files/scripts/android/launch-android-desktop.sh|nix-devshells/shells/scripts/launch-android-desktop.sh"
  "nix-presets/files/scripts/android/launch-emulator-daemon.sh|nix-devshells/shells/scripts/launch-emulator-daemon.sh"
  "nix-presets/files/scripts/android/launch-scrcpy-client.sh|nix-devshells/shells/scripts/launch-scrcpy-client.sh"
  "nix-presets/files/scripts/android/launch-vault.sh|nix-devshells/shells/scripts/launch-vault.sh"
  "nix-presets/files/scripts/android/simulate-fingerprint.sh|nix-devshells/shells/scripts/simulate-fingerprint.sh"
)

# Compare by stripping the marker comment block from each file and diffing.
# The marker comments are line 2 + line 3 (added by the SOURCE/MIRROR tagging),
# so we ignore any line containing one of these well-known strings.
strip_markers() {
  grep -v -e 'SOURCE OF TRUTH:' \
    -e 'MIRROR OF:' \
    -e 'Mirror at ' \
    -e 'Do not edit here' \
    "$1"
}

errors=0
for pair in "${PAIRS[@]}"; do
  src="${pair%%|*}"
  mirror="${pair##*|}"

  if [ ! -f "$src" ] || [ ! -f "$mirror" ]; then
    echo "❌ missing file in pair: $src | $mirror"
    errors=$((errors + 1))
    continue
  fi

  if diff -q <(strip_markers "$src") <(strip_markers "$mirror") >/dev/null 2>&1; then
    echo "✅ in sync: $(basename "$src")"
  else
    echo "⚠️  DRIFTED: $(basename "$src")"
    diff <(strip_markers "$src") <(strip_markers "$mirror") | head -10
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo
  echo "❌ $errors mirror(s) drifted. Treat nix-presets as source of truth and re-copy."
  exit 1
fi
