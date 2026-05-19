# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **meta-workspace** — a root flake that aggregates multiple independent sub-flakes via git submodules into one cohesive NixOS environment. It does not contain most configuration logic itself; it orchestrates sub-repos that do.

## Key Commands

All common operations go through `just`. Run `just` (no args) to open an fzf-based interactive hub.

```bash
# Environment
direnv allow              # Load devshell (preferred)
nix develop               # Pure fallback

# System deployment
just apply                # Stage → update lock → check → switch → sync agent
just apply-fast           # Same, but skips the eval check (faster)
just apply-boot           # Like apply, but sets new config as boot default
just nixos::switch        # Raw nixos-rebuild switch via `nh`
just nixos::test          # Activate config without making it the boot default
just nixos::dry-run       # Show what would change

# Validation & linting
just maintenance::check           # Eval the primary host (nixos-nvme)
just maintenance::check-all       # Eval + check all sub-flakes
just maintenance::check-hosts     # Full check of nix-config flake
just maintenance::lint            # Run treefmt --fail-on-change
just maintenance::fmt             # Format all Nix and shell code (treefmt)
just nixos::sys-plan              # Diff current system vs new build (nvd)

# Updates
just maintenance::update-local    # nix flake update (root)
just maintenance::update-all      # Update everything + flatpaks + apply

# Cleanup
just maintenance::clean           # Delete old generations, GC

# Git (operates across all sub-repos)
just status                       # Dashboard showing dirty/clean per repo
just git::save "message"          # Commit in all dirty repos + root
just git::push                    # Push all repos
just git::pull                    # Pull --rebase all repos

# Fleet deployment
just deployment::deploy-fleet     # Colmena deploy to all hosts
just deployment::deploy-orin      # Deploy to Orin Nano only

# Diagnostics
just maintenance::health-check    # AI log health check
just ai::ai-check                 # Check Ollama / vLLM status
just maintenance::who             # Show who holds the workspace lock
```

## Flake Hierarchy

```
nix (this repo — meta-workspace)
└── nix-config       ← primary consumer; owns host definitions
    ├── nix-devshells ← shared dev shells and tools
    ├── nix-hardware  ← device-specific hardware modules
    ├── nix-presets   ← reusable service/desktop bundles
    ├── nix-packages  ← custom packages (NUR-style)
    ├── nix-templates ← project scaffolding
    └── nix-secrets   ← sops-encrypted secrets (flake = false)
```

All sub-flakes are git submodules under the repo root and are referenced as local `git+file://` inputs in `flake.nix`. The `OVERRIDES` variable in `common.just` generates `--override-input` flags so local edits are picked up without pushing.

## nix-config Structure

```
nix-config/
  hosts/<name>/        ← per-machine configurations (nixos-nvme, orin-nano, core-pi, …)
  modules/
    nixos/             ← system-level modules (services, virtualization, desktop)
    home-manager/      ← user-level modules (dotfiles, terminal tools)
    flake/             ← flake-level modules
    nix-on-droid/      ← Android phone config
  users/
    martin/            ← martin's home-manager config
    dhirujaan/         ← secondary user
  inventory.nix        ← master source for NixOS + OpenWrt infrastructure
  docs/SYSTEM_REFERENCE.md  ← ground truth for current nixpkgs revisions & service maps
```

**Always check `nix-config/docs/SYSTEM_REFERENCE.md`** before any configuration task — it lists the live nixpkgs commit, all managed hosts, and active services.

## Architecture: Switchboard Pattern

All modules in `nix-presets` and `nix-config/modules` follow the **Switchboard** pattern:

- Every module defaults to `enable = false`.
- Hosts explicitly opt in via their `configuration.nix` or a `bundle.nix`.
- All custom options live under the `my.*` namespace (e.g., `my.desktop.enable = true`).

## Code Standards

**Attribute merging** — never repeat top-level attribute paths:
```nix
# Bad
my.desktop.enable = true;
my.services.ai.enable = true;

# Good
my = {
  desktop.enable = true;
  services.ai.enable = true;
};
```

- Format with `nixfmt` (run via `just maintenance::fmt` / `treefmt`).
- Secrets: use `sops-nix`. Access via `config.sops.secrets."name".path`. Never commit secrets.
- Remove unused variables and empty `let in` blocks (statix enforces this).
- Strings: double quotes for simple strings, `''` for multi-line.

## Devshells

The root `devenv.nix` imports `nix-devshells.devenvModules.default`. Specialized shells are exposed as `devenv.shells` in `flake.nix`:

| Shell | Purpose |
|---|---|
| `default` | Meta-workspace (just, gh, lazygit, workspace-status) |
| `apps` | General application tooling |
| `ai-dev` | AI/ML development stack |
| `pentest` | Security testing tools |
| `math` | Scientific computing (octave, etc.) |
| `media` | Media processing |
| `ultimate` | All of the above combined |

Enter a specific shell: `nix develop .#<name>` or `devenv shell <name>`.

## Ground Truth & Agent Context

- **System reference**: `nix-config/docs/SYSTEM_REFERENCE.md` — nixpkgs revisions, hosts, services.
- **Inventory**: `nix-config/inventory.nix` — master for both NixOS and OpenWrt infrastructure.
- **Agent rules**: `.agent/rules.md` and `.agent/rules/coding_standards.md`.
- **Decisions**: `.agent/decisions/` — ADRs for non-obvious architectural choices.
- After changes, run `just maintenance::sync-agent` to regenerate the system reference.
