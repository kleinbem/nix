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
            nix flake check ./$repo --impure {{OVERRIDES}} {{args}} 2>&1 | grep -v "does not match any input" || true; \
        fi; \
    done
    @echo "------------------------------------------------------------"
    @echo "🌐 Auditing root workspace (Aggregated Checks)..."
    @{{TIMER}} nix flake check . {{OVERRIDES}} {{args}} 2>&1 | grep -v "does not match any input" || true
    @echo "------------------------------------------------------------"
    @echo "✅ All workspace checks completed!"

[group("Linter")]
check-hosts *args="--impure":
    @echo "🏗️  Verifying all Host Configurations (Evaluation & Build)..."
    @{{TIMER}} nix flake check ./nix-config {{OVERRIDES}} {{args}}

[group("Linter")]
check-containers *args="--impure":
    @echo "📦 Verifying all Container Presets (Evaluation Test)..."
    @{{TIMER}} nix flake check ./nix-presets {{OVERRIDES}} {{args}}

[group("Linter")]
ci:
    @just maintenance::check-all

[group("Linter")]
check:
    @echo "✅ Verifying NixOS configuration..."
    @{{TIMER}} nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel {{OVERRIDES}} --impure

[group("Linter")]
check-shells:
    @bash ./scripts/verify-devshells.sh

[group("Security")]
audit *args="":
    @echo "🕵️ Running security audit..."
    @{{TIMER}} nix run nixpkgs#vulnix -- --system {{args}}

[group("Cleanup")]
[confirm("🧹 This will delete OLD system generations. Proceed?")]
clean *args="":
    @echo "🧹 Cleaning up workspace and system..."
    @{{TIMER}} nix-env --delete-generations +{{KEEP}} {{args}}
    @{{TIMER}} nix-collect-garbage -d {{args}}
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
    @{{LOCK_CMD}} {{TIMER}} just git::stage-all
    @{{LOCK_CMD}} {{TIMER}} just maintenance::update-local
    @{{LOCK_CMD}} {{TIMER}} just maintenance::check
    @{{LOCK_CMD}} {{TIMER}} just nixos::switch
    @{{LOCK_CMD}} {{TIMER}} just maintenance::sync-agent

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
    @nix flake update {{OVERRIDES}} {{args}}

[group("Updates")]
update-local:
    @just maintenance::update-core

[group("Updates")]
sync-agent:
    @echo "🤖 Syncing system context for Antigravity..."
    @./scripts/sync-agent-context.sh

[group("Updates")]
lock-refresh:
    @echo "🔄 Refreshing all sub-flake lock files..."
    @for repo in {{REPOS}}; do \
        if [ -f "$repo/flake.nix" ]; then \
            echo "Updating $repo..."; \
            nix flake update --flake "./$repo" || echo "Failed to update $repo"; \
        fi; \
    done

[group("System")]
who:
    #!/usr/bin/env python3
    import fcntl, os, sys
    lock_file = "/tmp/workspace-just.lock"
    if not os.path.exists(lock_file):
        print("✅ No active workspace lock found.")
        sys.exit(0)
    try:
        with open(lock_file, "r") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print("✅ Lock file exists but is NOT held by any active process.")
    except (IOError, OSError):
        # The lock is held. We can try to find the PID if we wrote it, 
        # but flock usually doesn't store the PID in the file.
        # However, we can use 'ps' to see who is running 'just'.
        print("🕵️ Workspace is LOCKED. Active tasks:")
        os.system("ps -eo pid,user,start,command | grep -E 'just|nixos-rebuild|nh os' | grep -v grep")
    except Exception as e:
        print(f"❌ Error checking lock: {e}")

update-all *args="":
    @echo "🚀 Starting Comprehensive System Update (Bluefin Style)..."
    @nix flake update {{OVERRIDES}} {{args}}
    @echo "📦 Updating Flatpaks..."
    @flatpak update -y
    @echo "🏗️  Applying system changes..."
    @just apply
    @echo "✅ System fully updated and synced!"
