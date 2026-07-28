---
description: High-level context, goals, and architecture of the workspace
---

# Project Context: `kleinbem` Workspace

## 1. Project Goals

- **Reproducibility**: Entire system defined in NixOS Flakes.
- **Security**: Hardware-backed secrets (YubiKey + Sops), Secure Boot (Lanzaboote), and strict firewalling.
- **AI-Augmented**: Workspace designed for Agentic AI usage (Antigravity/Gemini), with clear context and rules.
- **Hybrid Infrastructure**: Manages both Workstations (NixOS) and Network Infrastructure (OpenWrt routers).

## 2. Architecture: "Domain-Driven Namespace"

The workspace is NOT a monorepo. It is a collection of independent repositories grouped by domain.

```text
~/Develop/github.com/kleinbem/
├── kleinbem.code-workspace  # [VSCODE] Unifies all domains
├── Justfile                 # [ORCHESTRATOR] Delegates commands
├── .agent/                  # [CONTEXT] Rules and Workflows
├── nix/                     # [DOMAIN] General Computing
│   ├── nix-config/          # Main NixOS Flake (flake-parts)
│   └── nix-secrets/         # Private secrets (Sops)
└── openwrt/                 # [DOMAIN] Networking
    └── openwrt-builder/     # Router Image Builder
```

## 3. Tech Stack

- **Configuration**: NixOS + Home Manager + Flake-Parts.
- **Secrets**: `sops-nix` (Age + Yubikey).
- **Virtualization**: Podman + Nixpak (Sandboxing).
- **CI/CD**: Local-first (Justfile + GitHub Runners).
- **Networking**: OpenWrt (Filogic/MediaTek).

## 4. Key Constraints

- **Root is NOT a Git Repo**: Never run git commands at the root.
- **Always use `just`**: Do not run manual `nixos-rebuild` commands; use the Justfile abstraction.
