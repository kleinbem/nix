#!/usr/bin/env bash
cd nix-presets || exit
deadnix --edit .
statix fix .
git add -u
git commit -m "style: fix trailing unused lambda argument id"
cd .. || exit
git add nix-presets
git commit -m "chore: update submodule pointers after deadnix fixes"
