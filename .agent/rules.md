# AI Assistant Rules

## Core Principles
1.  **Best Practice**: Follow established Nix/NixOS best practices (e.g., modularity, reproducibility).
2.  **Minimalism**: Use as little code as possible. Delete dead code. Avoid over-engineering.
3.  **Think Twice**: Plan before acting. Verify assumptions.
4.  **Verify**: Always run checks (`just check`) to validate changes.

## Workflow
- **Use `just`**: Prefer `just <command>` (e.g., `just switch`, `just check`) over raw shell commands.
- **Formatting**: Keep all Nix code formatted.

## Architecture
- **Meta-Workspace**: This repo (`nix`) aggregates sub-flakes (`nix-config`, `nix-hardware`, etc.).
- **Dependency Flow**: `nix-config` consumes other local flakes.

## System Context
- **Ground Truth**: Always check `nix-config/docs/SYSTEM_REFERENCE.md` to find current `nixpkgs` revisions and service maps. For router-specific hardware and network maps, see `../openwrt/docs/SYSTEM_REFERENCE.md`.
- **Inventory Owner**: This repository owns the `nix-config/inventory.nix`, which is the master source for both NixOS and OpenWrt infrastructure.
- **Router Management**: Use `just deployment::router-provision` and `just deployment::deploy-router-lxc` for network-level operations.
- **Sync**: If the reference seems outdated, run `just maintenance::sync-agent`.
