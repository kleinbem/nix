import 'common.just'

set working-directory := ".."

# --- Validation & Maintenance ---

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
check-hosts *args="--impure":
    @echo "🏗️  Verifying all Host Configurations (Evaluation & Build)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check ./nix-config {{OVERRIDES}} {{args}}

[group("Linter")]
check-containers *args="--impure":
    @echo "📦 Verifying all Container Presets (Evaluation Test)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check ./nix-presets {{OVERRIDES}} {{args}}

[group("Linter")]
ci:
    @just maintenance::check-all

[group("Linter")]
check:
    @echo "✅ Verifying NixOS configuration..."
    @{{LOCK_CMD}} {{TIMER}} nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel {{OVERRIDES}} --impure

[group("Linter")]
check-shells:
    @bash ./scripts/verify-devshells.sh

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

[group("Cachix")]
cache-auth token:
    @cachix authtoken {{token}}

[group("Cachix")]
cache-use name="kleinbem":
    @cachix use {{name}}

[group("Cachix")]
cache-push name="kleinbem":
    @echo "⬆️ Pushing build results to {{name}}..."
    @{{LOCK_CMD}} nix build --no-link --print-out-paths . {{OVERRIDES}} | cachix push {{name}}

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

[private]
_apply switch_target auth="":
    #!/usr/bin/env bash
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    just git::stage-all
    just maintenance::update-local
    just maintenance::check
    just nixos::{{switch_target}} "{{auth}}"
    just maintenance::sync-agent

[group("Workflow")]
apply auth="":
    @just maintenance::_apply "switch" "{{auth}}"

[group("Workflow")]
apply-fast auth="" *args="":
    #!/usr/bin/env bash
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    just git::stage-all
    just maintenance::update-local
    just nixos::switch "{{auth}}" "" {{args}}
    just maintenance::sync-agent

[group("Workflow")]
apply-boot auth="":
    @just maintenance::_apply "switch-boot" "{{auth}}"

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
clean-launchers *args:
    @echo "🚀 Cleaning broken launchers..."
    @bash ./nix-config/scripts/clean-launchers.sh {{args}}

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

[group("Updates")]
sync-agent:
    @echo "🤖 Syncing system context for Antigravity..."
    @./scripts/sync-agent-context.sh

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
    @python3 ./scripts/audit_locks.py

[group("System")]
who:
    @python3 ./scripts/check_lock.py

update-all *args="":
    @echo "🚀 Starting Comprehensive System Update (Bluefin Style)..."
    @{{LOCK_CMD}} nix flake update {{OVERRIDES}} {{args}}
    @echo "📦 Updating Flatpaks..."
    @flatpak update -y
    @echo "🏗️  Applying system changes..."
    @just apply
    @echo "✅ System fully updated and synced!"
