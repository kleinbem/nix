import 'common.just'

set working-directory := ".."

# --- Workspace VCS operations (jj-only) ---
#
# Every commit/log/push/branch op flows through jj. Signing is automatic
# via the file-based NoTouch key (`sign-all = true` in jj config) — no
# agent, no PIN, no touch, no -S flag.
#
# jj operates per-repo. These recipes loop over all submodules and the
# meta-workspace, calling jj inside each. Submodule pointer bumps in the
# meta are captured by jj describe like any other file change.
#
# Genuine submodule-orchestration operations (init / sync / hard-reset)
# are intentionally not included — when needed, git is the right tool
# and clear enough to type directly. The previous `sync-all` and
# `resign-legacy` recipes have been removed.

# --- Status / read-only ---

[group("Status")]
status-all:
    @echo "📊 Workspace Status (jj)"
    @printf "%-30s %s\n" "REPOSITORY" "STATE"
    @printf "%-30s %s\n" "------------------------------" "----------------------------"
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        change=$(cd $repo && jj log -r @ --no-graph -T 'change_id.short() ++ " " ++ if(empty, "(empty)", "")' 2>/dev/null); \
        diff=$(cd $repo && jj diff --stat 2>/dev/null | tail -1); \
        printf "%-30s %s — %s\n" "$name" "$change" "$diff"; \
    done

# --- Sync ---

# Fetch from origin in every repo and rebase the working-copy change
# onto the new remote main.
[group("Sync")]
pull-all:
    @echo "📥 Fetching + rebasing all repositories..."
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        echo "  $name..."; \
        (cd $repo && jj git fetch && jj rebase -d main@origin 2>&1 | grep -v 'Nothing changed' || true); \
    done

# Describe (commit) any dirty change in every repo, advance the main
# bookmark so the new commit is the published tip, then start a fresh
# empty change. Submodules first so the meta pointer bump reflects
# their new HEADs.
#
# The bookmark-move is the bit jj doesn't do automatically — without
# it, the new commit sits "between" main and the empty @, and
# `git push` complains about detached HEAD.
[group("Sync")]
save-all message:
    @echo "💾 Saving workspace state: {{message}}"
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        if [ -n "$(cd $repo && jj diff --summary 2>/dev/null)" ]; then \
            echo "  📝 $name — describing..."; \
            (cd $repo && jj describe -m "{{message}}" && jj bookmark move main --to @ && jj new); \
        fi \
    done
    @echo "✅ Workspace state saved."

# Push every repo. `--allow-new` covers first push of a new bookmark.
[group("Sync")]
push-all:
    @echo "📤 Pushing all changes..."
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        echo "  $name..."; \
        (cd $repo && jj git push --allow-new 2>&1 | grep -v 'Nothing changed' || true); \
    done

# --- Branch management ---

# One-time setup per repo: tell jj that the local `main` bookmark
# tracks `main@origin`. Without this, `jj git push` warns about
# non-tracking bookmarks and refuses to push. Idempotent — safe to
# re-run across the whole workspace.
[group("Development")]
init-bookmarks:
    @echo "🔗 Linking local main <-> origin/main across workspace..."
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        echo "  $name..."; \
        (cd $repo && jj bookmark track main --remote=origin 2>&1 | grep -v 'already tracked' || true); \
    done

[group("Development")]
[confirm("🌿 This will create a new bookmark in ALL repositories. Continue?")]
branch-all name:
    @echo "🌿 Creating bookmark '{{name}}' across workspace..."
    @for repo in {{REPOS}} .; do \
        label=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        echo "  $label..."; \
        (cd $repo && jj bookmark create {{name}}); \
    done
