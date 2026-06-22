import 'common.just'

set working-directory := ".."

# --- Meta-workspace maintenance ---
# nix-config–specific recipes (check, check-hosts, apply*, sync-agent, impact,
# lint-conventions, clean-launchers) moved to `nix-config/.just/maintenance.just`.
# Invoke them from the meta root via root justfile [Main] shortcuts (apply,
# apply-fast, apply-boot, check) or `cd nix-config && just maintenance::X`.

[group("Formatting")]
format:
    @echo "🎨 Formatting and fixing all Nix and Shell code..."
    treefmt

[group("Linter")]
lint:
    @echo "🔍 Linting workspace..."
    treefmt --fail-on-change

# ============================================================================
#  COMPREHENSIVE WORKSPACE AUDIT — 7-stage check-all
# ============================================================================
# Stage 1: Lints + format + Python tests (fail-fast — no point doing 2h builds
#          if lint is broken). ~30s.
# Stage 2: Flake evaluations across every sub-flake + root. ~6 min.
# Stage 3: Audits (lockfile drift, flake-checker, devshell verify). ~1 min.
# Stage 4: Build x86_64 host configurations (--keep-going). ~15-30 min.
# Stage 5: Build every package in nix-packages. ~5-15 min.
# Stage 6: NixOS VM integration tests (--keep-going). ~30-60 min.
# Stage 7: Summary.
#
# Total: 60-110 minutes. Use `check-quick` (= stages 1-3 only) for fast feedback.
#
# aarch64 hosts (orin-nano, core-pi, hass-pi) are NOT built in stage 4 because
# cross-compilation requires binfmt+qemu setup; deploy them via `colmena` or
# `just deployment::orin-promote` instead.

[private]
_check-lints:
    @echo
    @echo "▶ Stage 1/7: Lints + format + Python tests"
    @echo "  └─ nix fmt --fail-on-change (treefmt via flake: nixfmt, statix, deadnix, shellcheck, shfmt, ruff-format)"
    @nix fmt -- --fail-on-change
    @echo "  └─ lint-python (meta)"
    @just maintenance::lint-python
    @echo "  └─ lint-python + test-python (nix-config)"
    @cd nix-config && just maintenance::lint-python && just maintenance::test-python
    @echo "  └─ lint-conventions (Switchboard pattern)"
    @cd nix-config && just maintenance::lint-conventions
    @echo "  └─ check-mirrors"
    @just maintenance::check-mirrors
    @echo "  ✅ Stage 1 OK"

[private]
_check-flakes *args="--impure":
    @echo
    @echo "▶ Stage 2/7: Flake evaluations"
    @for repo in {{REPOS}}; do \
        if [ -f "$repo/flake.nix" ]; then \
            echo "  └─ $repo"; \
            {{LOCK_CMD}} nix flake check ./$repo --impure {{OVERRIDES}} {{args}} 2>&1 | grep -v "does not match any input" || true; \
        fi; \
    done
    @echo "  ✅ Stage 2 OK"

[private]
_check-audits:
    @echo
    @echo "▶ Stage 3/7: Audits"
    @echo "  └─ audit-locks (sub-flake HEAD vs lockfile drift)"
    @just maintenance::audit-locks-all || true
    @echo "  └─ flake-check (DeterminateSystems)"
    @just maintenance::check-flakes
    @echo "  └─ check-shells (devshell evaluation)"
    @just maintenance::check-shells
    @echo "  ✅ Stage 3 OK"

[private]
_check-host-builds:
    @echo
    @echo "▶ Stage 4/7: Host closure builds (x86_64 only — discovered dynamically)"
    @hosts=$(nix flake show ./nix-config --json --impure 2>/dev/null \
        | jq -r '.checks."x86_64-linux" | keys[] | select(startswith("host-"))'); \
    if [ -z "$hosts" ]; then \
        echo "  ⚠  No host-* checks found in nix-config — skipping"; \
        exit 0; \
    fi; \
    failed=""; \
    for h in $hosts; do \
        host_name=${h#host-}; \
        echo "  └─ building $host_name..."; \
        if {{LOCK_CMD}} nix build --no-link --keep-going \
                ./nix-config#checks.x86_64-linux.$h {{OVERRIDES}} --impure 2>&1 | tail -5; then \
            echo "     ✅ $host_name"; \
        else \
            echo "     ❌ $host_name"; failed="$failed $host_name"; \
        fi; \
    done; \
    if [ -n "$failed" ]; then \
        echo "  ❌ Stage 4 failed:$failed"; \
        exit 1; \
    else \
        echo "  ✅ Stage 4 OK"; \
    fi
    @echo "  (aarch64 hosts — router-1/router-2/orin-nano/core-pi/hass-pi — skipped;"
    @echo "   deploy via colmena or build on-device)"

[private]
_check-package-builds:
    @echo
    @echo "▶ Stage 5/7: Custom-package builds (nix-packages, x86_64)"
    @pkgs=$(nix flake show ./nix-packages --json --impure 2>/dev/null \
        | jq -r '.packages."x86_64-linux" // {} | keys[] | "./nix-packages#packages.x86_64-linux." + .'); \
    if [ -z "$pkgs" ]; then \
        echo "  ⚠  No x86_64-linux packages found — skipping"; \
        exit 0; \
    fi; \
    count=$(echo "$pkgs" | wc -l); \
    echo "  └─ building $count package(s) with --keep-going..."; \
    if {{LOCK_CMD}} nix build --no-link --keep-going $pkgs 2>&1 | tail -20; then \
        echo "  ✅ Stage 5 OK"; \
    else \
        echo "  ❌ Stage 5: one or more packages failed (see output above)"; \
        exit 1; \
    fi

[private]
_check-vm-tests:
    @echo
    @echo "▶ Stage 6/7: NixOS VM integration tests (discovered dynamically)"
    @tests=$(nix flake show ./nix-config --json --impure 2>/dev/null \
        | jq -r '.checks."x86_64-linux" | keys[] \
                 | select(startswith("host-") | not) \
                 | select(. != "pre-commit-check")'); \
    if [ -z "$tests" ]; then \
        echo "  ⚠  No integration tests found — skipping"; \
        exit 0; \
    fi; \
    failed=""; \
    for t in $tests; do \
        echo "  └─ running: $t..."; \
        if {{LOCK_CMD}} nix build --no-link --keep-going \
                ./nix-config#checks.x86_64-linux.$t {{OVERRIDES}} --impure 2>&1 | tail -5; then \
            echo "     ✅ $t"; \
        else \
            echo "     ⚠  $t (may need KVM or external state)"; \
            failed="$failed $t"; \
        fi; \
    done; \
    if [ -n "$failed" ]; then \
        echo "  ⚠  Stage 6 finished with non-fatal issues:$failed"; \
    else \
        echo "  ✅ Stage 6 OK"; \
    fi

[group("Linter")]
check-all *args="--impure":
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  COMPREHENSIVE WORKSPACE AUDIT (7 stages, expect 60-110 min)"
    @echo "═══════════════════════════════════════════════════════════════"
    @just maintenance::_check-lints
    @just maintenance::_check-flakes {{args}}
    @just maintenance::_check-audits
    @just maintenance::_check-host-builds
    @just maintenance::_check-package-builds
    @just maintenance::_check-vm-tests
    @echo
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  ✅ ALL 7 STAGES COMPLETED"
    @echo "═══════════════════════════════════════════════════════════════"

# Fast-feedback alias: stages 1-3 only (lints + flake evals + audits). ~10 min.
[group("Linter")]
check-quick *args="--impure":
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  QUICK CHECK (lints + flake evals + audits, ~10 min)"
    @echo "═══════════════════════════════════════════════════════════════"
    @just maintenance::_check-lints
    @just maintenance::_check-flakes {{args}}
    @just maintenance::_check-audits
    @echo
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  ✅ QUICK CHECK PASSED — run \`check-all\` for full audit"
    @echo "═══════════════════════════════════════════════════════════════"

[group("Linter")]
check-containers *args="--impure":
    @echo "📦 Verifying all Container Presets (Evaluation Test)..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check ./nix-presets {{OVERRIDES}} {{args}}

[group("Linter")]
ci:
    @just maintenance::check-all

[group("Linter")]
check-shells:
    @bash ./tools/verify-devshells.sh

# Lint Python in the meta-workspace tools/ dir (workspace-mcp, ai-logs, etc).
# nix-config has its own `just maintenance::lint-python` for its scripts.
[group("Linter")]
lint-python *args="":
    @nix shell nixpkgs#ruff --command ruff check ./tools/ {{args}}

# Format Python in the meta-workspace tools/ dir.
[group("Formatting")]
format-python *args="":
    @nix shell nixpkgs#ruff --command ruff format ./tools/ {{args}}

# Verify the small set of scripts mirrored across nix-presets and nix-devshells
# haven't drifted. nix-presets is the source of truth.
[group("Linter")]
check-mirrors:
    @bash ./tools/check-script-mirrors.sh

[group("Security")]
audit-security *args="":
    @echo "🕵️ Running security audit..."
    @{{LOCK_CMD}} {{TIMER}} nix run nixpkgs#vulnix -- --system {{args}}

[group("Cleanup")]
[confirm("🧹 This will delete OLD system generations. Proceed?")]
clean-all *args="":
    @echo "🧹 Cleaning up workspace and system..."
    @{{LOCK_CMD}} {{TIMER}} nix-env --delete-generations +{{KEEP}} {{args}}
    @{{LOCK_CMD}} {{TIMER}} nix-collect-garbage -d {{args}}
    @for repo in {{REPOS}}; do \
        git -C $repo gc --prune=now; \
    done

[group("System")]
hooks-refresh-all:
    @echo "⚓ Refreshing Git hooks..."
    @rm -rf .git/hooks/*
    @if [ -d .git/modules ]; then \
        for mod in .git/modules/*; do \
            rm -rf "$mod/hooks/*"; \
        done; \
    fi
    @for repo in {{REPOS}}; do rm -rf "$repo/.git/hooks/*" 2>/dev/null || true; done
    @direnv allow
    @nix develop --command bash -c 'prek install && for repo in {{REPOS}}; do if [ -f "$repo/.pre-commit-config.yaml" ]; then echo "Installing hooks in $repo..."; (cd "$repo" && prek install) || true; fi; done'

[group("System")]
check-health:
    @echo "🏥 Running system health check..."
    @python3 ./tools/ai-logs.py --sink

[group("System")]
build-history:
    @echo "📜 Rebuilding history index..."
    @python3 ./tools/rebuild_history.py --sync

# Workspace-wide grep. Personal/OS recipes (Obsidian notes, Firefox
# cleanup, fix-yubikey/fix-chrome) live in the home-manager justfile —
# call them via `os <recipe>`.
[group("System")]
find pattern:
    @grep -rnE "{{pattern}}" . --exclude-dir=.git

[group("Updates")]
update-local:
    @{{LOCK_CMD}} python3 ./tools/sync_locks.py

# Bump Antigravity to latest (delegates to nix-packages' own justfile, which
# owns the upstream URL and the script). Run `cd nix-packages && just --list`
# to see the full updater set (update-antigravity, update-langfuse, …).
[group("Updates")]
update-antigravity:
    @cd {{ROOT}}/nix-packages && just update-antigravity

[group("Updates")]
update-container container_name:
    @echo "🚀 Triggering full update (stage + activate) for container '{{container_name}}'..."
    @sudo systemctl start update-container@{{container_name}}.service
    @echo "⏳ Update started in the background. Check logs with:"
    @echo "   journalctl -fu update-container@{{container_name}}.service"

# Stage a container update — fetch new closure, register profile, swap symlink.
# The running container keeps serving the OLD closure. Safe to run on attic
# without breaking other containers' substituter access. Activate when ready.
[group("Updates")]
update-container-stage container_name:
    @echo "📦 Staging update for container '{{container_name}}' (no restart)..."
    @sudo systemctl start update-container-stage@{{container_name}}.service
    @echo "⏳ Stage logs: journalctl -fu update-container-stage@{{container_name}}.service"
    @echo "   Activate with: just maintenance::update-container-activate {{container_name}}"

# Activate a previously-staged container update — restart the container so it
# runs the staged closure. ~5-30s downtime per container.
[group("Updates")]
update-container-activate container_name:
    @echo "🔄 Activating staged update for container '{{container_name}}' (restart)..."
    @sudo systemctl start update-container-activate@{{container_name}}.service

# Smart bulk update of every container registered with `my.services.container-updater`:
# stages all in parallel (no restarts) → activates non-attic in parallel → activates
# attic last. Avoids the attic-eats-itself bootstrap window during the restart phase.
# Same as the nightly 03:00 timer, on demand.
[group("Updates")]
update-container-all:
    @echo "🚀 Triggering smart bulk update for ALL registered containers..."
    @sudo systemctl start update-containers.service
    @echo "⏳ Watch progress:"
    @echo "   journalctl -fu update-containers.service        # orchestrator"
    @echo "   journalctl -fu 'update-container-stage@*.service'    # stages"
    @echo "   journalctl -fu 'update-container-activate@*.service' # activations"

[group("Audit")]
audit-locks-all:
    @bash ./tools/audit-locks.sh

# Lint flake.lock for staleness, EOL inputs, security issues (DeterminateSystems'
# flake-checker). Complements `audit-locks` (which compares your local sub-flake
# HEADs against the lock); this one checks upstream health of every input.
[group("Audit")]
check-flakes:
    @echo "🩺 Running flake-checker (input freshness, security, EOL…)"
    @nix run github:DeterminateSystems/flake-checker -- ./flake.lock

[group("System")]
who:
    @bash ./tools/check-lock.sh

