#!/usr/bin/env bash
cd nix-config || exit
deadnix --edit .
statix fix .
git add modules/nixos/data-disk.nix
git commit -m "fix(luks): add device timeout 0 to crypttab to prevent switch hangs"
