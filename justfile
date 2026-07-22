# Meta-Workspace Justfile
import '.just/common.just'

# --- Modules ---
mod jj '.just/jj.just'
mod ai '.just/ai.just'
mod deployment '.just/deployment.just'
mod maintenance '.just/maintenance.just'
mod devshell '.just/devshell.just'
mod extensions '.just/extensions.just'

# Recipes moved to `nix-config/justfile` (call directly with `cd nix-config && just X::Y`,
# or via shortcuts in the [Main] group below):
#   mod nixos    — nixos::switch, build, test, dry-run, sys-plan, attic-*, …
#   mod orin     — orin::ping, shell, stats, logs, …
#   mod android  — android::phone, tablet, phone-push, phone-backup-fetch
#   mod ai       (host-side only — ai::ai-check, ai-shell, ai-logs)
# The meta `mod ai` above retains: sync-all, distill-session, architect, code, plan, local, distill

[group("Main")]
default:
    @just hub

[group("Main")]
apply *args="":
    @cd nix-config && just dev::apply {{args}}

[group("Main")]
check:
    @cd nix-config && just dev::check

[group("Main")]
attic-coverage host="$(hostname)":
    @cd nix-config && just dev::attic-coverage {{host}}

[group("Main")]
check-shells:
    @just maintenance::check-shells

[group("Main")]
switch *args="":
    @cd nix-config && just nixos::switch {{args}}

[group("Main")]
status-all:
    @just jj::status-all

# Pass-through to any sub-flake's justfile from the meta root.
# Usage:
#   just in nix-config nixos::switch
#   just in nix-presets check
#   just in nix-secrets edit secrets.yaml
[group("Main")]
in repo *args:
    @cd {{repo}} && just {{args}}

[group("Main")]
audit-locks-all:
    @just maintenance::audit-locks-all

[group("Main")]
phone *args:
    @cd nix-config && just android::phone {{args}}

[group("Main")]
phone-push:
    @cd nix-config && just android::phone-push

[group("Main")]
phone-backup-fetch:
    @cd nix-config && just android::phone-backup-fetch

[group("Main")]
tablet *args:
    @cd nix-config && just android::tablet {{args}}


# --- Workspace Hub (fleet-aware, linutil-style browser) ---
# A read-only overlay over `just` recipes from BOTH the meta root and
# nix-config: two-level tree (categories → recipes), ⭐ Common + 🚢 By Host
# virtual categories. Recipes stay defined in their own repo; the hub only
# discovers + dispatches (nix-config recipes run via `just in nix-config …`).
# Implementation lives in tools/workspace-hub.sh.

[group("Main")]
hub:
    @bash {{justfile_directory()}}/tools/workspace-hub.sh

