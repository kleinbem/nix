#!/usr/bin/env nix-shell
# shellcheck shell=bash
#!nix-shell -i bash -p go

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# `go run` builds into a temp dir, so the sink can't be found from the binary.
export AI_LOGS_ROOT="${AI_LOGS_ROOT:-$(dirname "$SCRIPT_DIR")}"

# Run the Go implementation
cd "$SCRIPT_DIR/ai-logs"
exec go run main.go "$@"
