#!/usr/bin/env bash
metadata=$(nix flake metadata --json)
echo "$metadata" | jq -r '.nodes | to_entries[] | select(.value.locked.narHash != null) | "\(.key): \(.value.locked.narHash)"'
