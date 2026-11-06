#!/usr/bin/env nix-shell
# shellcheck shell=bash
#!nix-shell -i bash -p go

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The index lands in nix/scratch/, where atlas_mcp's semantic_search reads it.
export INDEXER_NIX_ROOT="${INDEXER_NIX_ROOT:-$(dirname "$SCRIPT_DIR")}"

# Run the Go implementation
cd "$SCRIPT_DIR/workspace-indexer"
exec go run main.go
