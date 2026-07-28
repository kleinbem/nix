---
description: High-level context, goals, and architecture of the workspace
---

# Project Context: `kleinbem` Workspace

## 1. Project Goals

- **Reproducibility**: Entire system defined in NixOS Flakes.
- **Security**: Hardware-backed secrets (YubiKey + Sops), Secure Boot (Lanzaboote), and strict firewalling.
- **AI-Augmented**: Workspace designed for Agentic AI usage (Antigravity/Gemini), with clear context and rules.
- **Hybrid Infrastructure**: Manages both Workstations (NixOS) and Network Infrastructure (OpenWrt routers).

## 2. Architecture: Federated Meta-Workspaces

The workspace is NOT a monorepo. `nix/` and `openwrt/` are each their own colocated
git+jj repo acting as a tooling-only conductor (own `justfile`, `repos.nix`,
`.agent/`) for a domain. Their sub-flakes/sub-repos are **flat siblings** under
the workspace root — not nested inside the conductor dir, not git submodules.
Each conductor's `just` recipes resolve them via `{{ROOT}}` (justfiles) or
`../` (shell scripts, `.envrc`).

```text
~/Develop/github.com/kleinbem/       # workspace root — NOT a git repo itself
├── kleinbem/                 # profile/meta repo (README, .code-workspace)
├── nix/                      # [CONDUCTOR] General Computing — own git+jj repo
├── nix-config/                 Main NixOS Flake (flake-parts)
├── nix-secrets/                Private secrets (Sops)
├── nix-presets/ nix-hardware/ nix-devshells/ nix-packages/ nix-templates/
├── github-config/              GitHub governance (Terraform)
├── openwrt/                  # [CONDUCTOR] Networking — own git+jj repo
├── openwrt-builder/            Router Image Builder
├── openwrt-config/             Ansible runtime config
└── openwrt-secrets/            Router secrets (Sops)
```

## 3. Tech Stack

- **Configuration**: NixOS + Home Manager + Flake-Parts.
- **Secrets**: `sops-nix` (Age + Yubikey).
- **Virtualization**: Podman + Nixpak (Sandboxing).
- **CI/CD**: Local-first (Justfile + GitHub Runners).
- **Networking**: OpenWrt (Filogic/MediaTek).

## 4. Key Constraints

- **The workspace root (`~/Develop/github.com/kleinbem/`) is NOT a git repo**: each domain dir (`nix/`, `openwrt/`) and each sibling sub-repo is its own independent git+jj repo. Run git/jj commands inside the specific repo you're changing.
- **Always use `just`**: Do not run manual `nixos-rebuild` commands; use the justfile abstraction.
