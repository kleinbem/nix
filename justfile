# Meta-Workspace Justfile
import '.just/common.just'

# --- Modules ---
mod git '.just/git.just'
mod nixos '.just/nixos.just'
mod android '.just/android.just'
mod ai '.just/ai.just'
mod deployment '.just/deployment.just'
mod maintenance '.just/maintenance.just'
mod devshell '.just/devshell.just'
mod orin '.just/orin.just'

[group("Main")]
default:
    @just hub

[group("Main")]
apply:
    @just maintenance::apply

[group("Main")]
apply-fast *args="":
    @just maintenance::apply-fast {{args}}

[group("Main")]
apply-boot:
    @just maintenance::apply-boot

[group("Main")]
check-shells:
    @just maintenance::check-shells

[group("Main")]
switch *args:
    @just nixos::switch {{args}}

[group("Main")]
status:
    @just git::status

[group("Main")]
audit-locks:
    @just maintenance::audit-locks

[group("Main")]
phone *args:
    @just android::phone {{args}}

[group("Main")]
phone-push:
    @just android::phone-push

[group("Main")]
phone-backup-fetch:
    @just android::phone-backup-fetch

[group("Main")]
tablet *args:
    @just android::tablet {{args}}


# --- Workspace Hub (Premium Interactive Menu) ---

[group("Main")]
hub:
    #!/usr/bin/env bash
    set -e
    # Categorize recipes with icons for a premium feel
    LIST=$(just --summary | tr ' ' '\n' | sort | awk '{
        icon="🛠️";
        if ($1 ~ /^android::/) icon="📱";
        else if ($1 ~ /^git::/) icon="🔄";
        else if ($1 ~ /^nixos::/) icon="🏗️";
        else if ($1 ~ /^ai::/) icon="🤖";
        else if ($1 ~ /^devshell::/) icon="💻";
        else if ($1 ~ /^deployment::/) icon="🚀";
        else if ($1 ~ /^maintenance::/) icon="🧹";
        else if ($1 ~ /^orin::/) icon="🏎️";
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

