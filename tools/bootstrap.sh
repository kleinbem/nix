#!/usr/bin/env bash
# The fresh-machine entry point — run this BEFORE `just` anything else.
#
# nix/justfile's `import '.just/common.just'` and `mod jj '.just/jj.just'`
# both point at symlinks into ../kleinbem/.just/ (the shared, canonical
# copies — see kleinbem/.just/jj.just). A missing import/mod target fails
# `just` for the ENTIRE justfile, not just the recipe that needed it — so on
# a truly fresh clone of just this repo, `just` won't even parse until
# kleinbem/ exists. This script breaks that chicken-and-egg: it can't read
# kleinbem/repos.nix (that's inside the thing it's fetching), so the clone
# URL below is the one hardcoded exception in the whole workspace.
#
# This file is deliberately NOT shared/symlinked with openwrt/tools/bootstrap.sh
# — its entire job is to work before any shared file is reachable.
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
