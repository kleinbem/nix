---
priority: critical
role: Orchestrator
description: "Project Rules and Architecture"
---

# Domain-Driven Namespace Architecture

This workspace is organized into **Domains**:

1.  **`nix/`**: General NixOS infrastructure.
    -   `nix/nix-config`: Main system configuration (Flake-Parts).
    -   `nit/nix-secrets`: Secure secrets (Sops).

2.  **`openwrt/`**: Router development.
    -   `openwrt/openwrt-builder`: Image builder.

## Orchestration

We use a **Root Justfile** for all common tasks.
**DO NOT** cd into subdirectories manually if a `just` command exists.

- `just nix system` -> Rebuilds NixOS
- `just nix dev` -> Enters dev shell
- `just router build <profile>` -> Builds router image

## Tools

- **Direnv**: usage is mandatory. Run `direnv allow` if prompted.
- **Sops**: Used for secret management.
- **Flake-Parts**: The Nix configuration framework.

## Key Constraints
-   **Root is NOT a Git Repo**: Never run git commands at the root.
-   **Always use `just`**: Do not run manual `nixos-rebuild` commands; use the Justfile abstraction.
