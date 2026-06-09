import 'common.just'

set working-directory := ".."

# --- Meta-workspace maintenance ---
# nix-config–specific recipes (check, check-hosts, apply*, sync-agent, impact,
# lint-conventions, clean-launchers) moved to `nix-config/.just/maintenance.just`.
# Invoke them from the meta root via root justfile [Main] shortcuts (apply,
# apply-fast, apply-boot, check) or `cd nix-config && just maintenance::X`.

[group("Formatting")]
fmt:
    @echo "🎨 Formatting and fixing all Nix and Shell code..."
    treefmt

[group("Formatting")]
fix:
    @just maintenance::fmt

[group("Linter")]
lint:
    @echo "🔍 Linting workspace..."
    treefmt --fail-on-change

[group("Linter")]
check-all *args="--impure":
    @echo "🧪 Starting Comprehensive Workspace Audit..."
    @echo "------------------------------------------------------------"
    @for repo in {{REPOS}}; do \
        if [ -f "$repo/flake.nix" ]; then \
            echo "🔍 Auditing sub-flake: $repo..."; \
            {{LOCK_CMD}} nix flake check ./$repo --impure {{OVERRIDES}} {{args}} 2>&1 | grep -v "does not match any input" || true; \
        fi; \
    done
    @echo "------------------------------------------------------------"
    @echo "🌐 Auditing root workspace (Aggregated Checks)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check . {{OVERRIDES}} {{args}} 2>&1 | grep -v "does not match any input" || true
    @echo "------------------------------------------------------------"
    @echo "✅ All workspace checks completed!"

[group("Linter")]
check-containers *args="--impure":
    @echo "📦 Verifying all Container Presets (Evaluation Test)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check ./nix-presets {{OVERRIDES}} {{args}}

[group("Linter")]
ci:
    @just maintenance::check-all

[group("Linter")]
check-shells:
    @bash ./scripts/verify-devshells.sh

# Lint Python in the meta-workspace scripts/ dir (workspace-mcp, ai-logs, etc).
# nix-config has its own `just maintenance::lint-python` for its scripts.
[group("Linter")]
lint-python *args="":
    @nix shell nixpkgs#ruff --command ruff check ./scripts/ {{args}}

# Format Python in the meta-workspace scripts/ dir.
[group("Formatting")]
fmt-python *args="":
    @nix shell nixpkgs#ruff --command ruff format ./scripts/ {{args}}

# Verify the small set of scripts mirrored across nix-presets and nix-devshells
# haven't drifted. nix-presets is the source of truth.
[group("Linter")]
check-script-mirrors:
    @bash ./scripts/check-script-mirrors.sh

[group("Security")]
audit *args="":
    @echo "🕵️ Running security audit..."
    @{{LOCK_CMD}} {{TIMER}} nix run nixpkgs#vulnix -- --system {{args}}

[group("Cleanup")]
[confirm("🧹 This will delete OLD system generations. Proceed?")]
clean *args="":
    @echo "🧹 Cleaning up workspace and system..."
    @{{LOCK_CMD}} {{TIMER}} nix-env --delete-generations +{{KEEP}} {{args}}
    @{{LOCK_CMD}} {{TIMER}} nix-collect-garbage -d {{args}}
    @for repo in {{REPOS}}; do \
        git -C $repo gc --prune=now; \
    done

[group("System")]
hooks-refresh:
    @echo "⚓ Refreshing Git hooks..."
    @rm -rf .git/hooks/*
    @for repo in {{REPOS}}; do rm -rf $repo/.git/hooks/*; done
    @direnv allow

[group("System")]
docs:
    @echo "📚 Generating configuration documentation..."
    @{{LOCK_CMD}} nix build .#docs

[group("System")]
health-check:
    @echo "🏥 Running system health check..."
    @python3 ./scripts/ai-logs.py --sink

[group("System")]
history:
    @echo "📜 Rebuilding history index..."
    @python3 ./scripts/rebuild_history.py --sync

[group("Notes")]
link-docs:
    @echo "🔗 Linking docs to Obsidian..."
    @ln -sf $(pwd)/docs $HOME/Documents/Notes/Project-Docs

[group("System")]
find pattern:
    @grep -rnE "{{pattern}}" . --exclude-dir=.git

[group("Notes")]
capture message="":
    @echo "📝 Capturing note..."
    @echo "- [ ] {{message}} (Captured on $(date))" >> $HOME/Documents/Notes/Inbox.md

[group("Notes")]
obsidian:
    @obsidian &

[group("Notes")]
organize-notes:
    @bash ./scripts/organize-notes.sh

[group("Notes")]
vault-check:
    @echo "🏠 Checking vault integrity..."
    @bash ./scripts/vault-health.sh

[group("Cleanup")]
[confirm("🦊 Delete all Firefox profile folders that aren't 'standard'?")]
clean-browsers:
    @echo "🦊 Cleaning browser profiles..."
    @find ~/.mozilla/firefox -maxdepth 1 -type d -name "*.default*" -not -path "*standard*" -delete

[group("Cleanup")]
[confirm("🧪 Reset the Firefox Laboratory profile? All data in that profile will be lost.")]
reset-firefox-laboratory:
    @echo "🧪 Resetting Laboratory profile..."
    @rm -rf ~/.mozilla/firefox/*.laboratory
    @firefox -P laboratory --headless &
    @sleep 3
    @pkill firefox

[group("Updates")]
[private]
update-core *args="":
    @{{LOCK_CMD}} nix flake update {{OVERRIDES}} {{args}}

[group("Updates")]
update-local:
    @{{LOCK_CMD}} python3 ./scripts/sync_locks.py

# Bump Antigravity to latest (delegates to nix-packages' own justfile, which
# owns the upstream URL and the script). Run `cd nix-packages && just --list`
# to see the full updater set (update-antigravity, update-langfuse, …).
[group("Updates")]
update-antigravity:
    @cd {{ROOT}}/nix-packages && just update-antigravity

[group("Updates")]
lock-refresh:
    @echo "🔄 Refreshing all sub-flake lock files with local overrides..."
    @for repo in {{REPOS}}; do \
        if [ -f "$repo/flake.nix" ]; then \
            echo "Updating $repo..."; \
            inputs=$(jq -r '.nodes.root.inputs | keys[]' "$repo/flake.lock" 2>/dev/null || true); \
            overrides=""; \
            for dep in {{REPOS}}; do \
                if echo "$inputs" | grep -q "^$dep$"; then \
                    overrides="$overrides --override-input $dep git+file://{{ROOT}}/$dep"; \
                fi; \
            done; \
            {{LOCK_CMD}} nix flake update --flake "./$repo" $overrides || echo "Failed to update $repo"; \
        fi; \
    done

[group("Audit")]
audit-locks:
    @bash ./scripts/audit-locks.sh

# Lint flake.lock for staleness, EOL inputs, security issues (DeterminateSystems'
# flake-checker). Complements `audit-locks` (which compares your local sub-flake
# HEADs against the lock); this one checks upstream health of every input.
[group("Audit")]
flake-check:
    @echo "🩺 Running flake-checker (input freshness, security, EOL…)"
    @nix run github:DeterminateSystems/flake-checker -- ./flake.lock

[group("System")]
who:
    @bash ./scripts/check-lock.sh

update-all *args="":
    @echo "🚀 Starting Comprehensive System Update (Bluefin Style)..."
    @{{LOCK_CMD}} nix flake update {{OVERRIDES}} {{args}}
    @echo "📦 Updating Flatpaks..."
    @flatpak update -y
    @echo "🏗️  Applying system changes..."
    @just apply
    @echo "✅ System fully updated and synced!"
