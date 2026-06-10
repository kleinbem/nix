#!/usr/bin/env bash
# Inspect the workspace flock at /tmp/workspace-just.lock (used by `just`
# recipes to serialize long-running builds). Shows whether it's held and
# by what.
#
# Replaces check_lock.py — the Python version did the same flock probe with
# more LoC. This is the bash equivalent.

set -euo pipefail

LOCK="/tmp/workspace-just.lock"

if [ ! -e "$LOCK" ]; then
  echo "✅ No active workspace lock found."
  exit 0
fi

# Try to take a non-blocking exclusive lock. If we can, nobody else holds it.
if flock -n "$LOCK" -c true 2>/dev/null; then
  echo "✅ Lock file exists but is NOT held by any active process."
else
  echo "🕵️  Workspace is LOCKED. Active tasks:"
  # Use pgrep -af (shellcheck SC2009 — preferred over grepping ps output).
  pgrep -af 'just|nixos-rebuild|nh os|nix build|nix eval' || true
fi
