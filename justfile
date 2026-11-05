# Meta-Workspace Justfile
import '.just/common.just'

# --- Modules ---
mod jj '.just/jj.just'
mod ai '.just/ai.just'
mod deployment '.just/deployment.just'
mod maintenance '.just/maintenance.just'
mod devshell '.just/devshell.just'
mod extensions '.just/extensions.just'

# Host-side modules (nixos, orin, android, the host part of ai) live in
# nix-config/justfile; the [Main] group below has shortcuts into them.

[group("Main")]
default:
    @just hub

[group("Main")]
apply *args="":
    @cd {{ROOT}}/nix-config && just dev::apply {{args}}

[group("Main")]
check:
    @cd {{ROOT}}/nix-config && just dev::check

[group("Main")]
attic-coverage host="$(hostname)":
    @cd {{ROOT}}/nix-config && just dev::attic-coverage {{host}}

[group("Main")]
check-shells:
    @just maintenance::check-shells

[group("Main")]
switch *args="":
    @cd {{ROOT}}/nix-config && just nixos::switch {{args}}

[group("Main")]
status-all filter="":
    @just jj::status-all {{filter}}

[group("Main")]
save-all message="" filter="":
    @just jj::save-all "{{message}}" {{filter}}

[group("Main")]
diff-all filter="" *args="":
    @just jj::diff-all {{filter}} {{args}}

[group("Main")]
pull-all filter="":
    @just jj::pull-all {{filter}}

[group("Main")]
push-all filter="":
    @just jj::push-all {{filter}}

[group("Main")]
sign-unsigned filter="":
    @just jj::sign-unsigned {{filter}}

[group("Main")]
ship-all message="" filter="":
    @just jj::ship-all "{{message}}" {{filter}}

alias ship := ship-all

# Wrap any jj subcommand to commit as a specific persona (nix-only — reads
# nix-config/personas.nix). e.g. `just as daniel save-all "fix: ui polish"`
[group("Main")]
as persona *args:
    @KLEINBEM_PERSONA={{persona}} just jj::{{args}}

# e.g. `just in nix-config nixos::switch`, `just in nix-presets check`
# Pass-through to any sub-flake's justfile from the meta root.
[group("Main")]
in repo *args:
    @cd {{ROOT}}/{{repo}} && just {{args}}

[group("Main")]
audit-locks-all:
    @just maintenance::audit-locks-all

# --- Workspace Hub (fleet-aware, linutil-style browser) ---
# Browses recipes from both this root and nix-config; it only discovers and
# dispatches, recipes stay in their own repo. See tools/workspace-hub.sh.

[group("Main")]
hub:
    @bash {{justfile_directory()}}/tools/workspace-hub.sh

