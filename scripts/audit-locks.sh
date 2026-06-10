#!/usr/bin/env bash
# Compare flake.lock revisions against the current git HEAD of every local
# `nix-*` submodule. Reports drift.
#
# Replaces audit_locks.py — the previous Python version was ~120 lines of
# subprocess + JSON parsing. This is the equivalent with `nix flake metadata`
# doing the work natively.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCKS=$(nix flake metadata --json "$REPO_ROOT" 2>/dev/null | jq -c '.locks.nodes')

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

drift_count=0
for dir in "$REPO_ROOT"/nix-*; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")

  locked=$(echo "$LOCKS" | jq -r --arg n "$name" '.[$n].locked.rev // empty')
  if [ -z "$locked" ]; then
    printf "  %-20s %b(no lock entry — not a flake input?)%b\n" "$name" "$YELLOW" "$RESET"
    continue
  fi

  current=$(git -C "$dir" rev-parse HEAD)
  if [ "$locked" = "$current" ]; then
    printf "  %-20s %b✓ in sync%b  (%s)\n" "$name" "$GREEN" "$RESET" "${locked:0:12}"
  else
    printf "  %-20s %b⚠ DRIFT%b\n" "$name" "$RED" "$RESET"
    printf "    lock:  %s\n" "${locked:0:12}"
    printf "    head:  %s\n" "${current:0:12}"
    drift_count=$((drift_count + 1))
  fi
done

if [ "$drift_count" -gt 0 ]; then
  echo
  echo "ℹ  $drift_count drift(s) detected. Run \`just maintenance::update-local\` to sync."
  exit 1
fi
