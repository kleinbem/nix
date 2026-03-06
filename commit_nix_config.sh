#!/usr/bin/env bash
cd nix-config
git add modules/nixos/data-disk.nix
git commit -m "fix(luks): add device timeout 0 to crypttab to prevent switch hangs"
