#!/usr/bin/env nix-shell
#!nix-shell -i bash -p go

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the Go implementation
cd "$SCRIPT_DIR/workspace-guardian"
exec go run main.go
