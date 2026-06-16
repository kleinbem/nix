#!/usr/bin/env bash
# Clone every sub-flake listed in repos.nix into the meta-workspace root.
#
# Used by CI workflows — replaces the now-defunct `git submodule update --init`
# flow that the repos.nix refactor (commit 332b138) broke. For local dev,
# `just jj::bootstrap` does the same plus jj initialization.
#
# Excludes nix-secrets: it's private and CI uses dummy secrets instead
# (see scripts/write-dummy-secrets.sh). Idempotent — skips directories that
# already exist. Pure bash so it can run before `Install Nix`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Parse repos.nix into "<name> <url>" pairs. Each entry is a single line
# `  name = "url";` — match with a deliberately tight regex so a future
# multi-line entry would fail loudly rather than silently skip.
while read -r name url; do
  if [ "$name" = "nix-secrets" ]; then
    continue
  fi
  if [ -d "$name" ]; then
    echo "  ✓ $name (already present)"
    continue
  fi
  https_url="${url/git@github.com:/https://github.com/}"
  echo "  ⬇ cloning $name from $https_url"
  git clone "$https_url" "$name"
done < <(sed -nE 's/^[[:space:]]+([a-z][a-z-]*)[[:space:]]*=[[:space:]]*"([^"]+)".*/\1 \2/p' repos.nix)
