import 'common.just'

set working-directory := ".."

# --- Meta-workspace maintenance ---
# nix-config's own recipes live in nix-config/.just/; the root [Main] shortcuts
# (apply, check, switch) call into them.

# Format each sub-flake with its own nix fmt, plus tools/ via formatter-meta (no flake here).
[group("Formatting")]
format-all:
    @echo "🎨 Formatting all Nix/Shell/Python code (sub-flakes + meta)..."
    @for repo in {{REPOS}}; do \
        if [ "$repo" != "github-config" ] && [ -f "{{ROOT}}/$repo/flake.nix" ]; then echo "  └─ $repo"; ( cd "{{ROOT}}/$repo" && nix fmt ); fi; \
    done
    @echo "  └─ meta files"
    @nix run {{ROOT}}/nix-devshells#formatter-meta

[group("Linter")]
lint-all:
    @echo "🔍 Linting workspace (sub-flakes + meta)..."
    @for repo in {{REPOS}}; do \
        if [ "$repo" != "github-config" ] && [ -f "{{ROOT}}/$repo/flake.nix" ]; then echo "  └─ $repo"; ( cd "{{ROOT}}/$repo" && nix fmt -- --fail-on-change ) || exit 1; fi; \
    done
    @echo "  └─ meta files"
    @nix run {{ROOT}}/nix-devshells#formatter-meta -- --fail-on-change

# --- check-all: 1 lints (fail-fast), 2 flake evals, 3 audits, 4 x86_64 host
# builds, 5 nix-packages builds, 6 VM tests, 7 summary. Stage 4 skips aarch64
# hosts, which would need binfmt + qemu.

[private]
_check-lints:
    @echo
    @echo "▶ Stage 1/7: Lints + format + Python tests"
    @echo "  └─ nix fmt --fail-on-change per sub-flake (nixfmt, statix, deadnix, shellcheck, shfmt, ruff-format)"
    @# No flake.nix here, so `nix fmt` would abort; check each sub-flake instead.
    @for repo in {{REPOS}}; do \
        if [ "$repo" != "github-config" ] && [ -f "{{ROOT}}/$repo/flake.nix" ]; then \
            echo "    └─ $repo"; \
            ( cd "{{ROOT}}/$repo" && nix fmt -- --fail-on-change ) || exit 1; \
        fi; \
    done
    @echo "  └─ meta files (tools/, repos.nix) via formatter-meta"
    @nix run {{ROOT}}/nix-devshells#formatter-meta -- --fail-on-change
    @echo "  └─ lint-python (meta)"
    @just maintenance::lint-python
    @echo "  └─ lint-python + test-python (nix-config)"
    @cd {{ROOT}}/nix-config && just dev::lint-python && just dev::test-python
    @echo "  └─ lint-conventions (Switchboard pattern)"
    @cd {{ROOT}}/nix-config && just dev::lint-conventions
    @echo "  └─ check-mirrors"
    @just maintenance::check-mirrors
    @echo "  ✅ Stage 1 OK"

[private]
_check-flakes *args="--impure":
    @echo
    @echo "▶ Stage 2/7: Flake evaluations"
    @set -o pipefail; failed=""; \
    for repo in {{REPOS}}; do \
        if [ -f "{{ROOT}}/$repo/flake.nix" ]; then \
            echo "  └─ $repo"; \
            {{LOCK_CMD}} nix flake check {{ROOT}}/$repo --impure {{OVERRIDES}} {{args}} 2>&1 \
                | { grep -v "does not match any input" || true; } || failed="$failed $repo"; \
        fi; \
    done; \
    if [ -n "$failed" ]; then echo "  ❌ Stage 2 failed:$failed"; exit 1; fi
    @echo "  ✅ Stage 2 OK"

[private]
_check-audits:
    @echo
    @echo "▶ Stage 3/7: Audits"
    @echo "  └─ audit-locks (sub-flake HEAD vs lockfile drift)"
    @just maintenance::audit-locks-all || echo "  ⚠  lock drift found (advisory, not a failure)"
    @echo "  └─ flake-check (DeterminateSystems)"
    @just maintenance::check-flakes
    @echo "  └─ check-shells (devshell evaluation)"
    @just maintenance::check-shells
    @echo "  ✅ Stage 3 OK"

[private]
_check-host-builds:
    @echo
    @echo "▶ Stage 4/7: Host closure builds (x86_64 only — discovered dynamically)"
    @set -o pipefail; \
    hosts=$(nix flake show {{ROOT}}/nix-config --json --impure 2>/dev/null \
        | jq -r '.checks."x86_64-linux" | keys[] | select(startswith("host-"))') \
        || { echo "  ❌ nix flake show failed for nix-config"; exit 1; }; \
    if [ -z "$hosts" ]; then \
        echo "  ⚠  No host-* checks found in nix-config — skipping"; \
        exit 0; \
    fi; \
    failed=""; \
    for h in $hosts; do \
        host_name=${h#host-}; \
        echo "  └─ building $host_name..."; \
        if {{LOCK_CMD}} nix build --no-link --keep-going \
                {{ROOT}}/nix-config#checks.x86_64-linux.$h {{OVERRIDES}} --impure 2>&1 | tail -5; then \
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
    @set -o pipefail; \
    pkgs=$(nix flake show {{ROOT}}/nix-packages --json --impure 2>/dev/null \
        | jq -r '.packages."x86_64-linux" // {} | keys[] | "{{ROOT}}/nix-packages#packages.x86_64-linux." + .') \
        || { echo "  ❌ nix flake show failed for nix-packages"; exit 1; }; \
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
    @set -o pipefail; \
    tests=$(nix flake show {{ROOT}}/nix-config --json --impure 2>/dev/null \
        | jq -r '.checks."x86_64-linux" | keys[] \
                 | select(startswith("host-") | not) \
                 | select(. != "pre-commit-check")') \
        || { echo "  ❌ nix flake show failed for nix-config"; exit 1; }; \
    if [ -z "$tests" ]; then \
        echo "  ⚠  No integration tests found — skipping"; \
        exit 0; \
    fi; \
    failed=""; \
    for t in $tests; do \
        echo "  └─ running: $t..."; \
        if {{LOCK_CMD}} nix build --no-link --keep-going \
                {{ROOT}}/nix-config#checks.x86_64-linux.$t {{OVERRIDES}} --impure 2>&1 | tail -5; then \
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

# Default audit: all stages except the builds (4-5), which CI already caches in Attic.
[group("Linter")]
check-all *args="--impure":
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  WORKSPACE AUDIT (lints + evals + audits + VM tests)"
    @echo "═══════════════════════════════════════════════════════════════"
    @just maintenance::_check-lints
    @just maintenance::_check-flakes {{args}}
    @just maintenance::_check-audits
    @echo
    @echo "▶ Stages 4-5 (host + package builds) SKIPPED — CI build-all builds +"
    @echo "  caches these in Attic. Run \`just maintenance::check-full-all\` to build locally."
    @just maintenance::_check-vm-tests
    @echo
    @echo "═══════════════════════════════════════════════════════════════"
    @echo "  ✅ AUDIT COMPLETED (builds offloaded to CI)"
    @echo "═══════════════════════════════════════════════════════════════"

# Full local audit, builds included, for when CI/Attic can't be relied on (60-110 min).
[group("Linter")]
check-full-all *args="--impure":
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

# Quick check: stages 1-3 only (lints, flake evals, audits), ~10 min.
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
    @{{LOCK_CMD}} {{TIMER}} nix flake check {{ROOT}}/nix-presets {{OVERRIDES}} {{args}}

[group("Linter")]
ci:
    @just maintenance::check-all

[group("Linter")]
check-shells:
    @bash ./tools/verify-devshells.sh

# Lint Python in tools/ (nix-config has its own dev::lint-python).
[group("Linter")]
lint-python *args="":
    @nix shell nixpkgs#ruff --command ruff check ./tools/ {{args}}

# Format Python in the meta-workspace tools/ dir.
[group("Formatting")]
format-python *args="":
    @nix shell nixpkgs#ruff --command ruff format ./tools/ {{args}}

# Check scripts mirrored from nix-presets into nix-devshells haven't drifted.
[group("Linter")]
check-mirrors:
    @bash ./tools/check-script-mirrors.sh

# Check infra/{personas,inventory}.json match nix-config (fix: tools/gen-iac-data.sh).
[group("Linter")]
check-iac-data:
    @bash ./tools/check-iac-data.sh

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
        git -C {{ROOT}}/$repo gc --prune=now; \
    done

# Empty .git/hooks in every repo, then let prek reinstall where a .pre-commit-config.yaml exists.
[group("System")]
hooks-refresh-all:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "⚓ Refreshing Git hooks..."
    # Check before deleting, or the hooks are gone with nothing to put them back.
    command -v prek >/dev/null || { echo "❌ prek not on PATH: load the devshell (direnv allow)"; exit 1; }
    failed=()
    for repo in {{REPOS}}; do
        [ -e "{{ROOT}}/$repo/.git" ] || continue
        # A linked worktree has a .git file and shares the main checkout's hooks.
        hooks="{{ROOT}}/$repo/.git/hooks"
        if [ -d "$hooks" ]; then find "$hooks" -mindepth 1 -delete; fi
        if [ -f "{{ROOT}}/$repo/.pre-commit-config.yaml" ]; then
            echo "  └─ $repo"
            (cd "{{ROOT}}/$repo" && prek install) || failed+=("$repo")
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then echo "❌ prek install failed in: ${failed[*]}"; exit 1; fi

[group("System")]
check-health:
    @echo "🏥 Running system health check..."
    @./tools/ai-logs.sh --sink

[group("System")]
build-history:
    @echo "📜 Rebuilding history index..."
    @python3 ./tools/rebuild_history.py --sync

# Workspace-wide grep.
[group("System")]
find pattern:
    @grep -rnE --exclude-dir=.git -e {{quote(pattern)}} .

# Workstation-only: the "fully cached" test dry-runs nixos-nvme, not the other hosts.
[group("Updates")]
update-cached:
    #!/usr/bin/env bash
    set -uo pipefail
    lock={{ROOT}}/nix-config/flake.lock
    # Another locked run may be mid-update: don't back up or restore under it.
    if ! flock -n {{LOCK_FILE}} true; then
        echo "❌ Workspace locked at {{LOCK_FILE}}. Run \`just maintenance::who\` to check."; exit 1
    fi
    # Per-run backup, so a second run can't overwrite this one's.
    bak=$(mktemp "$lock.bak.XXXXXX")
    cp "$lock" "$bak"
    restore() { mv "$bak" "$lock"; echo "❌ $1: nix-config/flake.lock restored, sub-flake locks it already updated are not (check just status-all)"; exit 1; }
    echo "🔄 Updating lockfile (nix flake update)..."
    {{LOCK_CMD}} bash -c "cd {{ROOT}}/nix-config && nix flake update" || restore "Update failed"
    just maintenance::update-local || restore "Lock sync failed"
    echo "🔍 Checking if new updates require heavy local builds (evaluating checks)..."
    if ! output=$({{LOCK_CMD}} nix build --no-link --dry-run {{ROOT}}/nix-config#checks.x86_64-linux.host-nixos-nvme {{OVERRIDES}} --impure 2>&1); then
        echo "$output"
        echo "❌ Dry run failed (the new lock may not evaluate). Reverting flake.lock..."
        mv "$bak" "$lock"
        just maintenance::update-local
        exit 1
    fi
    if echo "$output" | grep -q "will be built:"; then
        echo "❌ Updates require local builds! Reverting flake.lock..."
        mv "$bak" "$lock"
        just maintenance::update-local
    else
        echo "✅ Updates are fully cached! Lockfile updated successfully."
        rm "$bak"
    fi

[group("Updates")]
update-local:
    @{{LOCK_CMD}} python3 ./tools/sync_locks.py

# Bump Antigravity via nix-packages' justfile, which has the other updaters too.
[group("Updates")]
update-antigravity:
    @cd {{ROOT}}/nix-packages && just update-antigravity

[group("Updates")]
update-container container_name:
    @echo "🚀 Triggering full update (stage + activate) for container '{{container_name}}'..."
    @sudo systemctl start update-container@{{container_name}}.service
    @echo "⏳ Update started in the background. Check logs with:"
    @echo "   journalctl -fu update-container@{{container_name}}.service"

# Stage a container update without restarting it (safe even for attic).
[group("Updates")]
update-container-stage container_name:
    @echo "📦 Staging update for container '{{container_name}}' (no restart)..."
    @sudo systemctl start update-container-stage@{{container_name}}.service
    @echo "⏳ Stage logs: journalctl -fu update-container-stage@{{container_name}}.service"
    @echo "   Activate with: just maintenance::update-container-activate {{container_name}}"

# Activate a staged container update (restarts it, ~5-30s downtime).
[group("Updates")]
update-container-activate container_name:
    @echo "🔄 Activating staged update for container '{{container_name}}' (restart)..."
    @sudo systemctl start update-container-activate@{{container_name}}.service

# Update all registered containers: stage all, then restart attic last so the others can still pull.
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

# Run flake-checker on nix-config's flake.lock (stale, EOL or insecure inputs).
[group("Audit")]
check-flakes:
    @echo "🩺 Running flake-checker (input freshness, security, EOL…)"
    @nix run github:DeterminateSystems/flake-checker/v0.2.15 -- {{quote(ROOT / "nix-config/flake.lock")}}

[group("System")]
who:
    @bash ./tools/check-lock.sh

