#!/usr/bin/env bash
# The fresh-machine entry point — run this BEFORE `just` anything else.
#
# The justfile imports .just/*.just, symlinks into ../kleinbem/.just/, and a
# missing import breaks the whole justfile. So this clones kleinbem/ first,
# with a hardcoded URL since repos.nix lives inside it.
# Not shared with openwrt/tools/bootstrap.sh: it must work before any shared
# file exists.
set -euo pipefail

# Two levels up from tools/: past nix/ itself, to the true workspace root
# where kleinbem/ is a sibling (matches {{ROOT}} in the shared justfiles).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ ! -d "$ROOT/kleinbem" ]; then
    echo "🌱 kleinbem/ missing — cloning it first (everything else depends on it)..."
    git clone git@github.com:kleinbem/kleinbem.git "$ROOT/kleinbem"
    (cd "$ROOT/kleinbem" && jj git init --colocate && jj bookmark track main --remote=origin)
else
    echo "✓ kleinbem/ already present."
fi

echo "▶ Continuing with the normal bootstrap (just jj::bootstrap)..."
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec just jj::bootstrap "$@"
