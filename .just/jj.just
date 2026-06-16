import 'common.just'

set working-directory := ".."

# --- Workspace VCS operations (jj-first) ---
#
# Every commit/log/push/branch op flows through jj. Signing is automatic
# via the file-based NoTouch key (`sign-all = true` in jj config) — no
# agent, no PIN, no touch, no -S flag.
#
# Each sub-flake listed in `repos.nix` is its own independent git+jj
# repo (NOT a git submodule — see `just jj::bootstrap`). The meta repo
# is also a colocated jj repo. These recipes loop over each sub-flake
# AND meta, calling jj inside each.
#
# Use `git` only for legacy rescue ops or destructive resets — none of
# those are wrapped here; type them directly when needed.

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

# Audit commits ahead of origin for missing/bad signatures.
# Surfaces the silent-unsigned-commit failure mode where jj describe
# from a non-interactive context (e.g. Claude subprocess) produced a
# commit without signing.
# Exit code is 0 if all clean, non-zero if any unsigned commits exist.
[group("Status")]
check-signatures:
    @echo "🔐 Signature audit (commits ahead of origin/main)"
    @echo "------------------------------------------------"
    @any_bad=0; \
    for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        unsigned=$(git -C $repo log --format='%H %G? %s' "origin/main..HEAD" 2>/dev/null \
            | awk '$2 != "G" && $2 != ""' || true); \
        if [ -n "$unsigned" ]; then \
            echo "❌ $name"; \
            echo "$unsigned" | awk '{printf "   %s [%s] %s\n", substr($1,1,12), $2, substr($0, index($0,$3))}'; \
            any_bad=1; \
        else \
            ahead=$(git -C $repo rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0); \
            if [ "$ahead" -eq 0 ]; then \
                echo "✓  $name (no commits ahead)"; \
            else \
                echo "✓  $name ($ahead commit(s), all signed)"; \
            fi; \
        fi; \
    done; \
    echo "------------------------------------------------"; \
    if [ "$any_bad" -eq 1 ]; then \
        echo "🔧 Fix with: just jj::sign-unsigned"; \
        exit 1; \
    else \
        echo "✅ All ahead-of-origin commits are signed"; \
    fi

# Sign every unsigned commit ahead of origin across the workspace.
# Each repo's first signing triggers one YubiKey PIN/touch (cached
# thereafter). Companion to check-signatures.
[group("Sync")]
sign-unsigned:
    @echo "🔐 Signing unsigned commits ahead of origin..."
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        ahead=$(git -C $repo rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0); \
        if [ "$ahead" -gt 0 ]; then \
            unsigned=$(git -C $repo log --format='%H %G?' "origin/main..HEAD" 2>/dev/null \
                | awk '$2 != "G" && $2 != ""' | wc -l); \
            if [ "$unsigned" -gt 0 ]; then \
                echo "  🖊️  $name — signing $unsigned commit(s)..."; \
                (cd $repo && jj sign -r 'main@origin..main' 2>&1 | grep -v '^$' || true); \
            fi; \
        fi; \
    done
    @echo "✅ Done. Verify: just jj::check-signatures"

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

# Describe (commit) dirty changes across the workspace.
#
# Per sub-flake: each has its own colocated jj — uses `jj describe`,
# advances main bookmark, starts fresh empty change.
#
# Meta: regular file changes (justfile, scripts/, devenv.nix, etc.)
# go through `jj describe` too — meta is also a colocated jj repo.
# Sub-flake directories are gitignored, so they never appear as changes
# here. Submodule pointer bumps are no longer a thing (see repos.nix).
[group("Sync")]
save-all message:
    @echo "💾 Saving workspace state: {{message}}"
    @author=""; if [ -n "${KLEINBEM_PERSONA:-}" ]; then \
        author=$(nix eval --raw --file nix-config/personas.nix --apply \
            "p: p.${KLEINBEM_PERSONA}.full-name + \" <\" + p.${KLEINBEM_PERSONA}.email + \">\"" 2>/dev/null); \
        echo "  🎭 Acting as: $author"; \
    fi; \
    for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        if [ -n "$(cd $repo && jj diff --summary 2>/dev/null)" ]; then \
            echo "  📝 $name — describing..."; \
            if [ -n "$author" ]; then \
                (cd $repo && jj describe -m "{{message}}" --author "$author" && jj bookmark move main --to @ && jj new); \
            else \
                (cd $repo && jj describe -m "{{message}}" && jj bookmark move main --to @ && jj new); \
            fi; \
        fi; \
    done
    @echo "✅ Workspace state saved."

# Wrap any jj subcommand to commit as a specific persona from
# personas.nix. The persona's full-name + email become the git author
# on every commit produced. Example:
#   just jj::as michael save-all "feat(presets): add stalwart container"
# becomes equivalent to setting Author: "Michael Gruber <michael@kleinbem.dev>"
# on each describe.
[group("Sync")]
as persona *args:
    @KLEINBEM_PERSONA={{persona}} just jj::{{args}}

# Push every repo. `--allow-new` covers first push of a new bookmark.
[group("Sync")]
push-all:
    @echo "📤 Pushing all changes..."
    @for repo in {{REPOS}} .; do \
        name=$([ "$repo" = "." ] && echo "(meta)" || echo "$repo"); \
        echo "  $name..."; \
        (cd $repo && jj git push 2>&1 | grep -v 'Nothing changed' || true); \
    done

# --- Bootstrap ---

# Sync = bootstrap (clone any missing) + pull-all (fetch + rebase existing).
# Run after pulling a fresh meta repo to catch any new sub-flakes added
# to repos.nix and update all existing checkouts.
[group("Development")]
sync:
    @just jj::bootstrap
    @just jj::pull-all

# Clone every sub-flake listed in repos.nix and initialize jj on it.
# Replaces the old `git submodule update --init` flow — meta no longer
# pins specific commits; each sub-flake clones at its own current main.
# Idempotent: skips any directory that already exists.
[group("Development")]
bootstrap:
    @echo "🌱 Bootstrapping workspace from repos.nix..."
    @for repo in $(nix eval --raw --file repos.nix --apply 'rs: builtins.concatStringsSep " " (builtins.attrNames rs)'); do \
        if [ -d "$repo" ]; then \
            echo "  ✓ $repo (already cloned)"; \
        else \
            url=$(nix eval --raw --file repos.nix --apply "rs: rs.\"$repo\""); \
            echo "  📦 cloning $repo from $url..."; \
            git clone "$url" "$repo"; \
            (cd "$repo" && jj git init --colocate && jj bookmark track main --remote=origin); \
        fi \
    done
    @echo "✅ Workspace bootstrapped."

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
