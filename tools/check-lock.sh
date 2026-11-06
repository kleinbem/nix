#!/usr/bin/env bash
# Show whether the workspace flock that serializes long-running `just` builds
# is held, and by what.

set -euo pipefail

# The lock common.just's LOCK_CMD takes (kleinbem/.just/common.just LOCK_FILE).
LOCK="/tmp/kleinbem-workspace-just.lock"

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
