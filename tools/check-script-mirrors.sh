#!/usr/bin/env bash
# Verifies that scripts mirrored between sibling repos have not drifted,
# ignoring the marker comment lines that differ on purpose.

set -euo pipefail

# $0-relative: jj workspaces have no .git, so git rev-parse fails there.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# nix-presets/nix-devshells are siblings of nix/; a workspace sits one level
# deeper (nix.ws/<name>/).
FLEET_ROOT="$(dirname "$REPO_ROOT")"
case "$FLEET_ROOT" in *.ws) FLEET_ROOT="$(dirname "$FLEET_ROOT")" ;; esac
cd "$FLEET_ROOT"

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
    diff <(strip_markers "$src") <(strip_markers "$mirror") | head -10 || true
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo
  echo "❌ $errors mirror(s) drifted. Treat nix-presets as source of truth and re-copy."
  exit 1
fi
