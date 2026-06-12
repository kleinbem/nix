#!/usr/bin/env nix-shell
# shellcheck shell=bash
#!nix-shell -i bash -p go

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the Go implementation
cd "$SCRIPT_DIR/workspace-indexer"
exec go run main.go
