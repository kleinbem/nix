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
check-all *args="--all-systems --impure":
    @echo "🧪 Starting Comprehensive Workspace Audit..."
    @echo "------------------------------------------------------------"
    @for repo in {{REPOS}}; do \
        if [ -f "$repo/flake.nix" ]; then \
            echo "🔍 Auditing sub-flake: $repo..."; \
            nix flake check ./$repo --all-systems --impure {{args}} 2>&1 | grep -v "does not match any input" || true; \
        fi; \
    done
    @echo "------------------------------------------------------------"
    @echo "🌐 Auditing root workspace (Aggregated Checks)..."
    @nix flake check . {{OVERRIDES}} {{args}} 2>&1 | grep -v "does not match any input" || true
    @echo "------------------------------------------------------------"
    @echo "✅ All workspace checks completed!"

[group("Linter")]
check-hosts *args="--all-systems --impure":
    @echo "🏗️  Verifying all Host Configurations (Evaluation & Build)..."
    @nix flake check . {{OVERRIDES}} {{args}} --regex 'checks\..*\.host-.*'

[group("Linter")]
check-containers *args="--impure":
    @echo "📦 Verifying all Container Presets (Evaluation Test)..."
    @nix flake check . {{OVERRIDES}} {{args}} --regex 'checks\..*\.module-.*'

[group("Linter")]
ci:
    @just maintenance::check-all

[group("Linter")]
check:
    @echo "✅ Verifying NixOS configuration..."
    @nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel {{OVERRIDES}} --impure

[group("Linter")]
check-shells:
    @bash ./scripts/verify-devshells.sh

[group("Security")]
audit *args="":
    @echo "🕵️ Running security audit..."
    @nix run nixpkgs#vulnix -- --system {{args}}

[group("Cleanup")]
[confirm("🧹 This will delete OLD system generations. Proceed?")]
clean *args="":
    @echo "🧹 Cleaning up workspace and system..."
    @nix-env --delete-generations +{{KEEP}} {{args}}
    @nix-collect-garbage -d {{args}}
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
    @nix build --no-link --print-out-paths . {{OVERRIDES}} | cachix push {{name}}

[group("System")]
hooks-refresh:
    @echo "⚓ Refreshing Git hooks..."
    @rm -rf .git/hooks/*
    @for repo in {{REPOS}}; do rm -rf $repo/.git/hooks/*; done
    @direnv allow

[group("System")]
docs:
    @echo "📚 Generating configuration documentation..."
    @nix build .#docs

[group("Workflow")]
apply:
    @just git::stage-all
    @just maintenance::update-local
    @just maintenance::check
    @just nixos::switch

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
    @nix flake update {{OVERRIDES}} {{args}}

[group("Updates")]
update-local:
    @just maintenance::update-core

[group("Updates")]
sync-agent:
    @echo "🤖 Syncing system context for Antigravity..."
    @./scripts/sync-agent-context.sh

[group("Updates")]
update-all *args="":
    @echo "🚀 Starting Comprehensive System Update (Bluefin Style)..."
    @nix flake update {{args}}
    @echo "📦 Updating Flatpaks..."
    @flatpak update -y
    @echo "🏗️  Applying system changes..."
    @just apply
    @just maintenance::sync-agent
    @echo "✅ System fully updated and synced!"
