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
    @cd nix-config && just maintenance::apply {{args}}

[group("Main")]
apply-fast *args="":
    @cd nix-config && just maintenance::apply-fast {{args}}

[group("Main")]
apply-boot *args="":
    @cd nix-config && just maintenance::apply-boot {{args}}

[group("Main")]
check:
    @cd nix-config && just maintenance::check

[group("Main")]
attic-coverage:
    @cd nix-config && just maintenance::attic-coverage

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


# --- Workspace Hub (Premium Interactive Menu) ---

[group("Main")]
hub:
    #!/usr/bin/env bash
    set -e
    # Categorize recipes with icons for a premium feel
    LIST=$(just --summary | tr ' ' '\n' | sort | awk '{
        icon="🛠️";
        if ($1 ~ /^android::/) icon="📱";
        else if ($1 ~ /^jj::/) icon="🔄";
        else if ($1 ~ /^nixos::/) icon="🏗️";
        else if ($1 ~ /^ai::/) icon="🤖";
        else if ($1 ~ /^devshell::/) icon="💻";
        else if ($1 ~ /^deployment::/) icon="🚀";
        else if ($1 ~ /^maintenance::/) icon="🧹";
        else if ($1 ~ /^orin::/) icon="🏎️";
        else if ($1 ~ /^extensions::/) icon="🧩";
        else if ($1 ~ /^(status|switch|phone|tablet|apply)/) icon="✨";
        print icon " " $1
    }')

    SELECTED=$(echo "$LIST" | fzf \
        --header "✨ Workspace Hub | [Enter] Run | [Ctrl-E] Edit | [Ctrl-H] Help" \
        --height 25 --reverse --ansi --info=inline --border --margin=1,2 --padding=1 \
        --preview "just --show {2}" --preview-window "right:60%:wrap" \
        --prompt "🔍 Search: " --pointer "➜" --marker "✓" \
        --color "header:italic:cyan,info:blue,prompt:yellow,pointer:red" \
        --bind "ctrl-e:execute($EDITOR justfile --line \$(grep -n \"^{2}:\" justfile | cut -d: -f1))+abort" \
        --bind "ctrl-h:execute(just --list {2} | less)+reload(echo \"$LIST\")"
    )

    [ -n "$SELECTED" ] && just $(echo "$SELECTED" | awk '{print $2}')

