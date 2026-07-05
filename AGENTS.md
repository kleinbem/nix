# AGENTS.md

Guidance for AI assistants (Claude Code, Gemini CLI, Codex, Aider, Antigravity, …) working in this repository. Tool-specific filenames (`CLAUDE.md`, `GEMINI.md`) are symlinks to this file.

## Overview

This is a **meta-workspace dir** — a tooling-only orchestrator for several independent flakes cloned via `repos.nix`. **There is no `flake.nix` at the meta root.** `nix-config` is the root flake everything builds from; the meta dir holds `just`, `repos.nix`, `.agent/`, the `jj` dashboard, and the `.envrc` that points direnv at `./nix-devshells#workspace`. Bootstrap a fresh checkout with `just jj::bootstrap`.

## Key Commands

All common operations go through `just`. Run `just` (no args) to open an fzf-based interactive hub.

**Two justfiles, two working directories.** The meta root and `nix-config/` each have their own justfile, and `nix-config`'s shadows the meta one when you're inside it. Recipes below are grouped by where they run.

### From the meta root (`nix/`)

```bash
# Environment
direnv allow              # Load the workspace shell from nix-devshells
nix develop ./nix-devshells#workspace   # Pure fallback (no direnv)

# System deployment (delegates into nix-config)
just apply                # Align sub-flakes → sync locks → eval → switch (see `just apply --help`)
just apply --fast         # Same, but skips the eval check
just apply --boot         # Activate AND set as boot default
just switch               # Raw nixos-rebuild switch (delegates to nixos::switch)
just check                # Eval the primary host (nixos-nvme)

# Validation & linting
just maintenance::check-all       # Eval + check all sub-flakes
just maintenance::check-quick     # Lints + flake evals + audits (~10 min)
just maintenance::check-full-all  # Full audit, all stages
just maintenance::lint-all        # Run treefmt --fail-on-change
just maintenance::format-all      # Format all Nix and shell code (treefmt)

# Updates & cleanup
just maintenance::update-local    # Sync lockfiles across sub-flakes (stages only, never commits)
just maintenance::clean-all       # Delete old generations, GC, git gc all repos

# Version Control (Jujutsu / jj operates across all sub-repos)
just jj::status-all               # Dashboard showing repo state + ahead-of-origin
just jj::save-all "message"       # Commit in all dirty repos + root
just jj::push-all                 # Push all repos
just jj::pull-all                 # Pull --rebase all repos
just jj::ship                     # Describe + sign + push (the everything button)

# Diagnostics
just maintenance::check-health    # AI log health check
just maintenance::who             # Show who holds the workspace lock
just deployment::fleet            # Container fleet status view (NOT a deploy)
```

### From `nix-config/`

```bash
just nixos::switch                # Raw nixos-rebuild switch via `nh`
just nixos::test                  # Activate config without making it the boot default
just nixos::sys-plan              # Diff current system vs new build (nvd)

just maintenance::check           # Eval the primary host (nixos-nvme)
just maintenance::check-hosts     # Full check of nix-config flake
just maintenance::sync-agent      # Regenerate docs/SYSTEM_REFERENCE.md

just deployment::deploy-fleet     # Colmena deploy to all hosts (out-of-band push)
just deployment::deploy-orin      # Deploy to Orin Nano only

just ai::ai-check                 # Check Ollama / vLLM status
```

## Flake Hierarchy

```
nix/ (meta workspace dir — NO flake.nix; tooling only: just, repos.nix, .agent/)
├── nix-config       ← ROOT FLAKE; owns hosts/checks/packages; CI runs from here
│   ├── nix-devshells ← shared dev shells (workspace + ultimate + per-language)
│   ├── nix-hardware  ← device-specific hardware modules
│   ├── nix-presets   ← reusable service/desktop bundles
│   ├── nix-packages  ← custom packages (NUR-style)
│   ├── nix-templates ← project scaffolding
│   └── nix-secrets   ← sops-encrypted secrets (flake = false)
└── (other peer dirs: tools/, .just/, .agent/, infra/)
```

All sub-flakes are **standalone git+jj repos** cloned under the meta dir (NOT git submodules — see `repos.nix` for the manifest, `just jj::bootstrap` to set up a fresh machine). They are referenced from `nix-config/flake.nix` as local `git+file://` inputs. The `OVERRIDES` variable in `common.just` generates `--override-input` flags so local edits are picked up without pushing.

## Deploy Model

**Pull-based via `system.autoUpgrade`** (NixOS-native). Each host that opts in (`my.deploy.autoUpgrade.enable = true`) runs a `system.autoUpgrade` timer that polls `github:kleinbem/nix-config?ref=production#<host>` on its schedule (default nightly 04:00 ±30min) and switches if the SHA has moved. The `production` tag is advanced automatically by `.github/workflows/promote-production.yaml` after a green build-all — never a failed build's SHA, so hosts only auto-deploy CI-validated commits.

Offline hosts catch up next cycle; no special handling. No inbound SSH credentials in CI. `just deployment::deploy-fleet` (colmena push) is still available locally for immediate / out-of-band deploys.

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

- Format with `nixfmt` (run via `just maintenance::format-all` / `treefmt`).
- Secrets: use `sops-nix`. Access via `config.sops.secrets."name".path`. Never commit secrets.
- Remove unused variables and empty `let in` blocks (statix enforces this).
- Strings: double quotes for simple strings, `''` for multi-line.

## Devshells

All devshells live in `nix-devshells`. Direnv at the meta dir loads `./nix-devshells#workspace` automatically (see `.envrc`).

| Shell | Purpose |
|---|---|
| `workspace` | Meta-workspace shell loaded by direnv: just, gh, lazygit, claude-code, workspace-status, ollama health check |
| `ultimate` | Composite of apps + pentest + ai-dev + math + media with inventory script |
| `apps` | General application tooling |
| `ai-dev` | AI/ML development stack |
| `pentest` | Security testing tools |
| `math` | Scientific computing (octave, etc.) |
| `media` | Media processing |
| `android` | Android tooling |
| `arm` | ARM cross-build environment |

Enter via `just devshell::<name>` (handles the path for you). Manual equivalent: `nix develop ./nix-devshells#<name>`.

## Ground Truth & Agent Context

- **System reference**: `nix-config/docs/SYSTEM_REFERENCE.md` — nixpkgs revisions, hosts, services.
- **Inventory**: `nix-config/inventory.nix` — master for both NixOS and OpenWrt infrastructure.
- **Agent rules**: `.agent/rules.md` and `.agent/rules/coding_standards.md`.
- **Decisions**: `.agent/decisions/` — ADRs for non-obvious architectural choices.
- After changes, run `just maintenance::sync-agent` to regenerate the system reference.
