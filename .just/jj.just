import 'common.just'

set working-directory := ".."

# --- Workspace VCS operations (jj-first) ---
#
# Every commit/log/push/branch op flows through jj. Each sub-flake listed
# in `repos.nix` is its own independent git+jj repo (NOT a git submodule
# — see `just jj::bootstrap`). The meta repo is also a colocated jj repo.
# These recipes loop over each sub-flake AND meta, calling jj inside each.
#
# Use `git` only for legacy rescue ops or destructive resets — none of
# those are wrapped here; type them directly when needed.
#
# TUI output uses `gum` (charmbracelet/gum) — install via `nix-env` or
# add to home-manager packages. Recipes degrade noticeably if absent
# (they call gum and the user sees "gum: command not found").
#
# --- Signing ---
#
# Today's reality: commits are signed via `git commit --amend -S` during
# `sign-unsigned`, which touches the YubiKey on every signing operation.
# TODO: wire a NoTouch SSH-FIDO key + `sign-all = true` in ~/.config/jj/
# config.toml so jj signs at describe-time without prompting. Until then,
# expect one YubiKey touch per repo per signing pass.

# --- Interactive hub ---

# Interactive launcher — fuzzy-pick a workspace operation. Great for
# muscle memory: just type `j` (or whatever alias) → pick.
[group("Status")]
hub:
    #!/usr/bin/env bash
    set -e
    choice=$(gum choose --header "📦 Workspace Operations" \
        "status-all       — repo state + ahead-of-origin counts" \
        "diff-all         — uncommitted changes across the workspace" \
        "remote-status    — GitHub dashboard (CI, PRs, issues)" \
        "remote-prs       — open PRs across the workspace" \
        "remote-ci        — recent CI runs per repo" \
        "check-signatures — audit signatures on commits ahead of origin" \
        "─────────────────────────────────────────────" \
        "pull-all         — fetch + rebase every sub-repo" \
        "save-all         — describe (commit) all dirty repos" \
        "sign-unsigned    — sign unsigned commits ahead of origin" \
        "push-all         — push every repo" \
        "─────────────────────────────────────────────" \
        "sync             — bootstrap + pull-all" \
        "init-bookmarks   — link local main to origin/main" \
        "quit")
    case "$choice" in
        status-all*)        just jj::status-all ;;
        diff-all*)          just jj::diff-all ;;
        remote-status*)     just jj::remote-status ;;
        remote-prs*)        just jj::remote-prs ;;
        remote-ci*)         just jj::remote-ci ;;
        check-signatures*)  just jj::check-signatures ;;
        pull-all*)          just jj::pull-all ;;
        save-all*)          msg=$(gum input --placeholder "Commit message"); just jj::save-all "$msg" ;;
        sign-unsigned*)     just jj::sign-unsigned ;;
        push-all*)          just jj::push-all ;;
        sync*)              just jj::sync ;;
        init-bookmarks*)    just jj::init-bookmarks ;;
        *) exit 0 ;;
    esac

# --- Status / read-only ---

# Compact workspace overview — change_id, @ state (described or not),
# and a count of described vs undescribed commits ahead of origin/main.
[group("Status")]
status-all:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📊 Workspace Status (jj)"
    {
        printf "REPO\tCHANGE\t@ STATE\tAHEAD OF ORIGIN\n"
        for repo in {{REPOS}} .; do
            name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
            change=$(cd $repo && jj log -r @ --no-graph -T 'change_id.short()' 2>/dev/null)
            empty=$(cd $repo && jj log -r @ --no-graph -T 'if(empty, "1", "0")' 2>/dev/null)
            desc=$(cd $repo && jj log -r @ --no-graph -T 'description.first_line()' 2>/dev/null)
            # Truncate long descriptions so gum table doesn't widen the column to
            # half the terminal. 60 chars is enough to recognise the change.
            desc_short="${desc:0:60}"
            [ "${#desc}" -gt 60 ] && desc_short="${desc_short}…"
            if [ "$empty" = "1" ]; then status_desc="(empty)";
            elif [ -z "$desc" ]; then status_desc="⚠ undescribed";
            else status_desc="📝 $desc_short"; fi
            described_n=$(cd $repo && jj log -r 'main@origin..@ & ~empty()' --no-graph -T 'if(description, "1\n", "")' 2>/dev/null | grep -c . || true)
            undescribed_n=$(cd $repo && jj log -r 'main@origin..@ & ~empty()' --no-graph -T 'if(description, "", "1\n")' 2>/dev/null | grep -c . || true)
            if [ "$described_n" -eq 0 ] && [ "$undescribed_n" -eq 0 ]; then ahead="(none)";
            elif [ "$undescribed_n" -eq 0 ]; then ahead="📝 $described_n ready";
            elif [ "$described_n" -eq 0 ]; then ahead="⚠ $undescribed_n undescribed";
            else ahead="📝$described_n ⚠$undescribed_n (mixed)"; fi
            printf "%s\t%s\t%s\t%s\n" "$name" "$change" "$status_desc" "$ahead"
        done
    } | gum table -s "$(printf '\t')" --print

# GitHub remote dashboard — origin/main SHA, latest CI status,
# open PR count, open issue count per repo. ~6s due to gh API roundtrips.
[group("Status")]
remote-status:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📡 Remote Workspace Status (GitHub)"
    out=$(gum spin --spinner dot --title "Querying GitHub..." --show-output -- bash -c '
        {
            printf "REPO\tMAIN\tCI\tPRs\tISSUES\n"
            for repo in {{REPOS}} .; do
                if [ "$repo" = "." ]; then name="nix"; ghrepo="kleinbem/nix";
                else name="$repo"; ghrepo="kleinbem/$repo"; fi
                sha=$(git -C $repo rev-parse --short origin/main 2>/dev/null || echo "?")
                ci=$(gh run list --repo $ghrepo --branch main --limit 1 --json conclusion,status \
                    --jq ".[0] | if .status==\"in_progress\" then \"🔄\" elif .conclusion==\"success\" then \"✅\" elif .conclusion==\"failure\" then \"❌\" elif .conclusion==\"cancelled\" then \"⏹\" else \"?\" end" 2>/dev/null || echo "—")
                prs=$(gh pr list --repo $ghrepo --state open --json number --jq "length" 2>/dev/null || echo "?")
                issues=$(gh issue list --repo $ghrepo --state open --json number --jq "length" 2>/dev/null || echo "?")
                printf "%s\t%s\t%s\t%s\t%s\n" "$name" "$sha" "$ci" "$prs" "$issues"
            done
        }
    ')
    echo "$out" | gum table -s "$(printf '\t')" --print

# Every open PR across the workspace as a flat table.
[group("Status")]
remote-prs:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔀 Open PRs across the workspace"
    out=$(gum spin --spinner dot --title "Fetching PRs..." --show-output -- bash -c '
        {
            printf "REPO\t#\tTITLE\tAUTHOR\n"
            for repo in {{REPOS}} .; do
                if [ "$repo" = "." ]; then name="nix"; ghrepo="kleinbem/nix";
                else name="$repo"; ghrepo="kleinbem/$repo"; fi
                gh pr list --repo $ghrepo --state open --json number,title,author \
                    --jq ".[] | \"$name\t#\(.number)\t\(.title)\t@\(.author.login)\"" 2>/dev/null || true
            done
        }
    ')
    n=$(echo "$out" | tail -n +2 | grep -c .)
    if [ "$n" -eq 0 ]; then
        gum style --foreground 46 "✓ No open PRs anywhere."
    else
        echo "$out" | gum table -s "$(printf '\t')" --print
    fi

# Recent CI workflow runs per repo as a single flat table.
[group("Status")]
remote-ci limit="5":
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🚦 Recent CI runs (last {{limit}} per repo)"
    out=$(gum spin --spinner dot --title "Fetching CI runs..." --show-output -- bash -c '
        {
            printf "REPO\tSTATUS\tWORKFLOW\tTITLE\n"
            for repo in {{REPOS}} .; do
                if [ "$repo" = "." ]; then name="nix"; ghrepo="kleinbem/nix";
                else name="$repo"; ghrepo="kleinbem/$repo"; fi
                gh run list --repo $ghrepo --limit {{limit}} --json conclusion,status,name,displayTitle \
                    --jq ".[] | \"$name\t\(if .status==\"in_progress\" then \"🔄\" elif .status==\"queued\" then \"⏳\" elif .conclusion==\"success\" then \"✅\" elif .conclusion==\"failure\" then \"❌\" elif .conclusion==\"cancelled\" then \"⏹\" elif .conclusion==\"skipped\" then \"⏭\" else \"?\" end)\t\(.name)\t\(.displayTitle)\"" 2>/dev/null || true
            done
        }
    ')
    echo "$out" | gum table -s "$(printf '\t')" --print

# Show the working-copy diff for every dirty sub-repo + meta in one go.
# Variadic — pass any `jj diff` flag through:
#   just jj::diff-all             # default jj diff
#   just jj::diff-all --git       # git-style
#   just jj::diff-all --stat      # stat summary
#   just jj::diff-all --color-words
[group("Status")]
diff-all *args="":
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔍 Workspace diff (per-repo, dirty only)"
    any=0
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        if [ -n "$(cd $repo && jj diff --summary 2>/dev/null)" ]; then
            any=1
            gum style --foreground 212 --padding "0 1" --margin "1 0 0 0" "📦 $name"
            (cd $repo && jj diff {{args}})
        fi
    done
    if [ "$any" -eq 0 ]; then
        gum style --foreground 46 --margin "1 0" "✓ Workspace clean — no uncommitted changes anywhere."
    fi

# Audit commits ahead of origin for missing signatures.
# Status codes (git's %G?):
#   G  good signature, verified locally
#   U  signed but signing key not in ~/.ssh/allowed_signers
#   B  bad signature (forgery/corruption)
#   N  NO signature — the real problem; GitHub will reject
#   E, X, Y, R  various error states
[group("Status")]
check-signatures:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔐 Signature audit (commits ahead of origin/main)"
    any_unsigned=0; any_unverified=0
    {
        printf "REPO\tCOMMITS\tSTATUS\tDETAIL\n"
        for repo in {{REPOS}} .; do
            name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
            lines=$(git -C $repo log --format='%H %G? %s' "origin/main..main" 2>/dev/null || true)
            unsigned=$(echo "$lines" | awk '$2 == "N" || $2 == "B" || $2 == "E"')
            unverified=$(echo "$lines" | awk '$2 == "U" || $2 == "X" || $2 == "Y" || $2 == "R"')
            ahead=$(echo "$lines" | grep -c . || true)
            if [ -n "$unsigned" ]; then
                first=$(echo "$unsigned" | head -1 | awk '{printf "[%s] %s", $2, substr($0, index($0,$3))}')
                printf "%s\t%s\t%s\t%s\n" "$name" "$ahead" "❌ UNSIGNED" "$first"
                any_unsigned=1
            elif [ -n "$unverified" ]; then
                first=$(echo "$unverified" | head -1 | awk '{printf "[%s] %s", $2, substr($0, index($0,$3))}')
                printf "%s\t%s\t%s\t%s\n" "$name" "$ahead" "⚠ unverified" "$first"
                any_unverified=1
            elif [ "$ahead" -eq 0 ] || [ -z "$lines" ]; then
                printf "%s\t0\t✓ none\t—\n" "$name"
            else
                printf "%s\t%s\t✓ all signed\t—\n" "$name" "$ahead"
            fi
        done
    } | gum table -s "$(printf '\t')" --print
    if [ "$any_unsigned" -eq 1 ]; then
        gum style --foreground 196 --margin "1 0" "🔧 Fix unsigned with: just jj::sign-unsigned"
        exit 1
    elif [ "$any_unverified" -eq 1 ]; then
        gum style --foreground 220 --margin "1 0" "ℹ Unverified ≠ rejected. Push will likely succeed; local mismatch is cosmetic."
    else
        gum style --foreground 46 --margin "1 0" "✅ All ahead-of-origin commits are signed and verified"
    fi

# Sign every unsigned commit ahead of origin across the workspace.
# Uses `git rebase --exec` rather than `jj sign` (more reliable).
# Auto-advances the local `main` bookmark to @ first if @ has a description
# and is ahead — so users can run `sign-unsigned` directly after `jj describe`
# without needing a redundant `push-all` to trigger the bookmark move.
# First operation per session may need a YubiKey PIN; cached thereafter.
[group("Sync")]
sign-unsigned:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔐 Signing unsigned commits ahead of origin"
    any_done=0
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        # Auto-advance: if @ has a description and is ahead of main bookmark,
        # move main to @ so the unsigned commit becomes visible to git.
        if [ -n "$(cd $repo && jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)" ]; then
            (cd $repo && jj bookmark move main --to @ >/dev/null 2>&1 || true)
        fi
        unsigned=$(git -C $repo log --format='%G?' "origin/main..main" 2>/dev/null \
            | awk '$1 != "G" && $1 != ""' | wc -l)
        if [ "$unsigned" -gt 0 ]; then
            gum style --foreground 212 "  🖊  $name — re-signing $unsigned commit(s)..."
            stashed=0
            if (cd $repo && git stash push -u -m "auto-stash for sign-unsigned" >/dev/null 2>&1); then
                stashed=1
            fi
            (cd $repo && git checkout main >/dev/null 2>&1 || true)
            if (cd $repo && git rebase --exec \
                'if [ "$(git log -1 --format=%G?)" != "G" ]; then git commit --amend --no-edit -S; fi' \
                origin/main); then
                if [ "$(git -C $repo symbolic-ref --quiet HEAD 2>/dev/null)" = "refs/heads/main" ]; then
                    (cd $repo && jj git import >/dev/null 2>&1) \
                        && gum style --foreground 46 "    ↳ main at signed HEAD; jj bookmark synced"
                else
                    (cd $repo && git branch -f main HEAD && git checkout main >/dev/null 2>&1 && jj git import >/dev/null 2>&1) \
                        && gum style --foreground 46 "    ↳ reattached main + jj bookmark"
                fi
                [ "$stashed" -eq 1 ] && (cd $repo && git stash pop >/dev/null 2>&1 || true)
            else
                [ "$stashed" -eq 1 ] && (cd $repo && git stash pop >/dev/null 2>&1 || true)
                gum style --foreground 196 "    ⚠ rebase failed in $name — fix manually"
            fi
            any_done=1
        fi
    done
    if [ "$any_done" -eq 0 ]; then
        gum style --foreground 46 --margin "1 0" "✓ Nothing to sign — all ahead-of-origin commits already signed"
    else
        gum style --foreground 46 --margin "1 0" "✅ Done. Verify with: just jj::check-signatures"
    fi

# --- Sync ---

# Fetch from origin in every repo and rebase the working-copy change.
[group("Sync")]
pull-all:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📥 Fetching + rebasing all repositories"
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd $repo && jj git fetch && jj rebase -d main@origin >/dev/null 2>&1 || true"
    done
    gum style --foreground 46 --margin "1 0" "✅ pull-all complete. Run: just jj::status-all"

# Describe (commit) dirty changes across the workspace.
# Prompts for message via gum input if not given.
#   just jj::save-all "feat: stalwart container"
#   just jj::save-all                  # prompts
[group("Sync")]
save-all message="":
    #!/usr/bin/env bash
    set -e
    msg="{{message}}"
    if [ -z "$msg" ]; then
        msg=$(gum input --header "Commit message" --placeholder "feat(...): ...")
    fi
    if [ -z "$msg" ]; then
        gum style --foreground 196 "❌ No message provided. Aborting."
        exit 1
    fi
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "💾 Saving workspace state: $msg"
    author=""
    if [ -n "${KLEINBEM_PERSONA:-}" ]; then
        author=$(nix eval --raw --file nix-config/personas.nix --apply \
            "p: p.${KLEINBEM_PERSONA}.full-name + \" <\" + p.${KLEINBEM_PERSONA}.email + \">\"" 2>/dev/null)
        gum style --foreground 99 "🎭 Acting as: $author"
    fi
    any=0
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        if [ -n "$(cd $repo && jj diff --summary 2>/dev/null)" ]; then
            any=1
            gum style --foreground 212 "  📝 $name — describing..."
            if [ -n "$author" ]; then
                (cd $repo && jj describe -m "$msg" --author "$author" && jj bookmark move main --to @ && jj new) >/dev/null 2>&1
            else
                (cd $repo && jj describe -m "$msg" && jj bookmark move main --to @ && jj new) >/dev/null 2>&1
            fi
        fi
    done
    if [ "$any" -eq 0 ]; then
        gum style --foreground 220 --margin "1 0" "✓ Workspace clean — nothing to describe."
    else
        gum style --foreground 46 --margin "1 0" "✅ Workspace state saved."
    fi

# Wrap any jj subcommand to commit as a specific persona.
[group("Sync")]
as persona *args:
    @KLEINBEM_PERSONA={{persona}} just jj::{{args}}

# Push every repo. Auto-advances main bookmark to @ if @ has a description
# and is ahead of local main. Covers the common describe-then-push flow.
[group("Sync")]
push-all:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📤 Pushing all changes"
    failed=()
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        output=$(gum spin --spinner dot --title "$name..." --show-output -- bash -c "
            cd $repo
            if [ -n \"\$(jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)\" ]; then
                jj bookmark move main --to @ >/dev/null 2>&1 || true
            fi
            jj git push 2>&1 | grep -v 'Nothing changed' || true
        ")
        if echo "$output" | grep -qE "error|rejected"; then
            failed+=("$name")
            gum style --foreground 196 "  ❌ $name"
            echo "$output" | sed 's/^/     /'
        elif echo "$output" | grep -q "move forward"; then
            gum style --foreground 46 "  ✅ $name — $(echo "$output" | grep -oE 'move forward.*')"
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then
        gum style --foreground 196 --margin "1 0" "❌ Failed: ${failed[*]}"
        gum style --foreground 220 "   ↳ Try: just jj::sign-unsigned (likely cause: signed-commit branch rules)"
        exit 1
    else
        gum style --foreground 46 --margin "1 0" "✅ All pushes complete."
    fi

# --- Bootstrap ---

# Sync = bootstrap (clone any missing) + pull-all.
[group("Development")]
sync:
    @just jj::bootstrap
    @just jj::pull-all

# Clone every sub-flake listed in repos.nix and initialize jj on it.
[group("Development")]
bootstrap:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🌱 Bootstrapping workspace from repos.nix"
    for repo in $(nix eval --raw --file repos.nix --apply 'rs: builtins.concatStringsSep " " (builtins.attrNames rs)'); do
        if [ -d "$repo" ]; then
            gum style --foreground 46 "  ✓ $repo (already cloned)"
        else
            url=$(nix eval --raw --file repos.nix --apply "rs: rs.\"$repo\"")
            gum spin --spinner dot --title "cloning $repo..." -- bash -c "
                git clone '$url' '$repo' >/dev/null 2>&1
                cd '$repo' && jj git init --colocate >/dev/null 2>&1 && jj bookmark track main --remote=origin >/dev/null 2>&1
            "
            gum style --foreground 46 "  ✓ $repo cloned + jj-initialised"
        fi
    done
    gum style --foreground 46 --margin "1 0" "✅ Workspace bootstrapped."

# One-time setup per repo: tell jj that main tracks main@origin.
[group("Development")]
init-bookmarks:
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔗 Linking local main ↔ origin/main"
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd $repo && jj bookmark track main --remote=origin 2>&1 | grep -v 'already tracked' || true"
    done
    gum style --foreground 46 --margin "1 0" "✅ Bookmark tracking ensured."

[group("Development")]
branch-all name:
    #!/usr/bin/env bash
    set -e
    gum confirm "🌿 Create bookmark '{{name}}' across ALL repositories?" || exit 0
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🌿 Creating bookmark '{{name}}'"
    for repo in {{REPOS}} .; do
        name=$([ "$repo" = "." ] && echo "nix" || echo "$repo")
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd $repo && jj bookmark create {{name}}"
    done
    gum style --foreground 46 --margin "1 0" "✅ Bookmark created in all repos."
