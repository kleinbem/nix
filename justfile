# Meta-Workspace Justfile
REPOS := `find . -maxdepth 1 -name "nix-*" -type d -printf "%f\n" | xargs echo`
# Use overrides to make local folders the "source of truth", bypassing flake.lock caching for local workspace repos
# Force 'path:' to ensure uncommitted changes are seen and Nix doesn't downgrade to stale Git commits
OVERRIDES := shell("echo " + REPOS + " | sed 's/\\([^ ]*\\)/--override-input \\1 path:$(pwd)\\/\\1/g'")

default:
    @just --list

# --- Git Operations ---

# Show status of all repositories in the workspace
status:
    @echo "📊 Workspace Status Dashboard"
    @printf "%-30s %-20s %-10s\n" "REPOSITORY" "BRANCH" "STATUS"
    @printf "%-30s %-20s %-10s\n" "------------------------------" "--------------------" "----------"
    @for repo in {{REPOS}}; do \
        branch=$(git -C $repo rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"); \
        stat="Clean"; \
        if [ -n "$(git -C $repo status --porcelain 2>/dev/null)" ]; then stat="Dirty ⚠️"; fi; \
        printf "%-30s %-20s %-10s\n" "$repo" "$branch" "$stat"; \
    done
    @branch=$(git rev-parse --abbrev-ref HEAD); \
    stat="Clean"; \
    if [ -n "$(git status --porcelain)" ]; then stat="Dirty ⚠️"; fi; \
    printf "%-30s %-20s %-10s\n" "(ROOT)" "$branch" "$stat"
 
# Stage changes in all repositories
stage-all:
    @echo "➕ Staging changes in all repositories..."
    @for repo in {{REPOS}}; do \
        if [ -n "$(git -C $repo status --porcelain 2>/dev/null)" ]; then \
            echo "Staging in $repo..."; \
            git -C $repo add .; \
        fi; \
    done
    @if [ -n "$(git status --porcelain)" ]; then \
        echo "Staging in (ROOT)..."; \
        git add .; \
    fi
    @echo "✅ All changes staged."

# Pull changes in all repositories
pull:
    git pull
    @for repo in {{REPOS}}; do git -C $repo pull; done

# Sync all submodules (init, update, sync, and clean state)
sync:
    @echo "🔄 Syncing all submodules..."
    git submodule sync --recursive
    git submodule update --init --recursive
    git submodule foreach 'git checkout main || git checkout master || true'
    git submodule foreach 'git reset --hard HEAD'
    @echo "✅ All submodules synced and cleaned."

# Save all changes (commit in sub-repos, then update meta-repo)
save message:
    @echo "💾 Saving changes across all repositories..."
    @for repo in {{REPOS}}; do \
        if [ -n "$(git -C $repo status --porcelain)" ]; then \
            echo "Committing in $repo..."; \
            git -C $repo add . && git -C $repo commit -m "{{message}}" || true; \
        fi \
    done
    @echo "Updating meta-repo pointers..."
    git add . && git commit -m "{{message}}" || true
    @echo "✅ All changes saved."

# Load YubiKey into SSH agent for signing
git-sign:
    @echo "🔑 Loading YubiKey into SSH agent..."
    ssh-add -K 2>/dev/null || true
    ssh-add ~/.ssh/id_ed25519_sk 2>/dev/null || true
    ssh-add ~/.ssh/id_ed25519_sk_backup 2>/dev/null || true
    @ssh-add -l | grep -q "SK" && echo "✅ YubiKey loaded." || echo "❌ YubiKey NOT found in agent."

# Push all changes to GitHub (with submodule check)
push:
    @echo "🚀 Pushing changes across all repositories..."
    @for repo in {{REPOS}}; do \
        echo "Pushing $repo..."; \
        git -C $repo push; \
    done
    @echo "Pushing meta-repo..."
    git push
    @echo "✅ All changes pushed."

# Clean up stale git references and temporary files
clean:
    @echo "🧹 Cleaning up workspace..."
    git submodule foreach 'git gc --prune=now && git remote prune origin'
    git gc --prune=now && git remote prune origin
    rm -rf .dev-dashboard
    @just clean-launchers --apply
    @echo "✅ Workspace cleaned."

# Clean up broken application launchers (~/.local/share/applications)
clean-launchers *args:
    @bash nix-config/scripts/clean-launchers.sh {{args}}

# Refresh all git hooks in the workspace and submodules to fix stale Nix store paths
hooks-refresh:
    @echo "🔄 Refreshing Git hooks..."
    @# Unset any stale core.hooksPath that might be pointing to dead Nix store paths
    @git config --unset-all core.hooksPath || true
    @if [ -f ".pre-commit-config.yaml" ]; then \
        pre-commit install --install-hooks --overwrite; \
    fi
    @for repo in {{REPOS}}; do \
        if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then \
            echo "Processing $repo..."; \
            (cd $repo && git config --unset-all core.hooksPath || true); \
            if [ -f "$repo/.pre-commit-config.yaml" ]; then \
                echo "Refreshing hooks in $repo..."; \
                (cd $repo && pre-commit install --install-hooks --overwrite); \
            else \
                echo "🧹 Cleaning up stale hooks in $repo..."; \
                (cd $repo && pre-commit uninstall 2>/dev/null || true); \
                echo "⏭️  Skipping $repo (no .pre-commit-config.yaml)"; \
            fi; \
        fi \
    done
    @echo "✅ Hooks refreshed."

# Prune unused Podman data (images, volumes, networks)
podman-prune:
    @echo "🧹 Pruning Host Podman Cache..."
    podman system prune -a -f
    @if systemctl is-active --quiet container@langfuse.service; then \
        echo "🧹 Pruning Nested Langfuse Podman Cache..."; \
        sudo machinectl shell langfuse /run/current-system/sw/bin/podman system prune -f; \
    fi

# --- NixOS Operations ---

# Switch System (Defaults to Local Overrides for Workspace)
# Usage: just switch OR just switch playground
switch mode="":
    @if [ -z "{{mode}}" ]; then \
        echo "🚀 Switching System (Minimal Mode)..."; \
        nice -n 19 ionice -c 3 nh os switch . -- {{OVERRIDES}} --impure; \
        bash nix-config/scripts/mode-info.sh minimal; \
    else \
        echo "🚀 Switching System & Activating Mode: {{mode}}..."; \
        nice -n 19 ionice -c 3 nh os switch . -- {{OVERRIDES}} --impure; \
        just mode {{mode}}; \
    fi

# Switch with Debug Output
switch-debug:
    @echo "🚀 Debug Switch (Verbose)..."
    nice -n 19 ionice -c 3 nh os switch . -- {{OVERRIDES}} --impure --show-trace --verbose

# Build the system (No Switch/Activation)
build:
    @echo "🏗️ Building System Configuration..."
    nice -n 19 ionice -c 3 nh os build . -- {{OVERRIDES}} --impure

# System Test (Build & Activate, No Bootloader)
test:
    @echo "🧪 Testing System Activation..."
    nice -n 19 ionice -c 3 nh os test . -- {{OVERRIDES}} --impure

# System Boot (Build & Bootloader only, No Switch)
switch-boot:
    @echo "👢 Preparing Next Boot..."
    nice -n 19 ionice -c 3 nh os boot . -- {{OVERRIDES}} --impure
    @if [ -d ./nix-config/scripts ]; then ./nix-config/scripts/tag-generation.sh; fi

# Boot with Debug Output
switch-boot-debug:
    @echo "👢 Debug Boot (Verbose)..."
    nice -n 19 ionice -c 3 nh os boot . -- {{OVERRIDES}} --impure --show-trace --verbose
    @if [ -d ./nix-config/scripts ]; then ./nix-config/scripts/tag-generation.sh; fi

# Full Workspace Pulse: Stage, Update, Check, Audit, and Switch in one go.
apply: stage-all update-local check audit switch
    @echo "✨ Workspace applied and activated."

# --- Workload Profile Management (Specialisations) ---

# List available system modes (specialisations)
modes:
    @echo "🎭 Available System Modes:"
    @if [ -d "/run/current-system/specialisation" ]; then \
        ls -F /run/current-system/specialisation | sed 's/\///'; \
    else \
        echo "No specialisations found. Run 'just switch' first."; \
    fi

# Switch to a specific system mode (live switch)
# Usage: just mode minimal
mode name:
    @if [ -d "/run/current-system/specialisation/{{name}}" ]; then \
        echo "🔄 Switching to mode: {{name}}..."; \
        sudo /run/current-system/specialisation/{{name}}/bin/switch; \
        bash nix-config/scripts/mode-info.sh {{name}}; \
        echo "✅ System is now in '{{name}}' mode."; \
    else \
        echo "❌ Mode '{{name}}' not found."; \
        just modes; \
    fi

# Reset system to the default (base) configuration
reset-mode:
    @echo "🏠 Resetting to base configuration..."
    @just switch



update-all:
    #!/usr/bin/env bash

    for repo in {{REPOS}}; do
        if [ -d "$repo" ] && [ -f "$repo/flake.nix" ]; then
            echo "Updating $repo..."
            (cd "$repo" && nix flake update {{OVERRIDES}} --impure)
        fi
    done
    echo "Updating ROOT..."
    nix flake update {{OVERRIDES}} --impure
    echo "✅ All flakes upgraded."

# Update only local workspace flake inputs
update-core:
    @echo "🔄 Updating core flake inputs (nixpkgs)..."
    nix flake update nixpkgs --impure
    @echo "✅ Core inputs updated."

update-local:
    @echo "🔄 Updating local workspace inputs..."
    nix flake update nix-config nix-presets nix-hardware nix-packages nix-devshells nix-templates nix-secrets {{OVERRIDES}} --impure
    @echo "✅ Local inputs updated."

# --- Validation & Maintenance ---

# Format all nix code
fmt:
    @echo "🎨 Formatting and fixing all Nix and Shell code..."
    @nix fmt {{OVERRIDES}} --impure
    @for repo in {{REPOS}}; do \
        if [ -d "$repo" ] && [ -f "$repo/flake.nix" ]; then \
            echo "Processing $repo..."; \
            (cd $repo && nix fmt); \
        else \
            echo "Skipping $repo (No flake.nix)..."; \
        fi; \
    done
    @echo "✅ All code formatted and fixed."

# Check NixOS Configuration (Skips DevShell check which fails in sandbox)
check:
    @echo "🔍 Checking NixOS Configuration..."
    @nice -n 19 ionice -c 3 nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel.drvPath {{OVERRIDES}} --impure >/dev/null
    @echo "✅ Configuration is Valid!"

# Review system changes before switching
sys-plan: build
    @echo "📊 Comparing current system with new build..."
    @nvd diff /run/current-system ./result
    @echo "---"
    @echo "✅ If you're happy with these changes, run 'just switch'."

# Run all linters without making changes
lint:
    @echo "🔍 Linting all code (Check mode)..."
    @nix fmt {{OVERRIDES}} --impure -- --fail-on-change
    @for repo in {{REPOS}}; do \
        if [ -d "$repo" ] && [ -f "$repo/flake.nix" ]; then \
            echo "Linting $repo..."; \
            (cd $repo && nix fmt -- --fail-on-change); \
        fi; \
    done
    @echo "✅ All checks passed!"

# Apply all automatic fixes and format code (Alias for fmt)
fix: fmt

# Generate documentation for custom NixOS options
docs:
    @echo "📚 Generating documentation for custom options..."
    @mkdir -p docs
    @nix eval --json .#nixosConfigurations.nixos-nvme.options.my {{OVERRIDES}} --impure --apply "opts: builtins.mapAttrs (n: v: { description = v.description or \"No description\"; default = v.default or \"No default\"; }) opts" > docs/options.json
    @echo "✅ Documentation generated in docs/options.json"

# Run security vulnerability audit on the entire infrastructure
audit:
    @sudo nix-security-audit all
    @echo "✅ Security Audit Complete."

# Dry Run System Activation
dry-run:
    @echo "🔍 Simulating NixOS Activation..."
    sudo nixos-rebuild dry-activate --flake .#nixos-nvme {{OVERRIDES}}

# Build and run a local VM of the system configuration
test-vm:
    @echo "🖥️ Building Test VM..."
    nixos-rebuild build-vm --flake .#nixos-nvme {{OVERRIDES}}
    @echo "🚀 Starting VM..."
    ./result/bin/run-nixos-nvme-vm

# Run NixOS VM Integration Tests
test-integration:
    @echo "🧪 Running Integration Tests..."
    nix flake check

# Full verification: Run flake check on all workspace members
check-all: check
    @echo "🔍 Checking Workspace Repositories..."
    @for repo in {{REPOS}}; do \
        if [ -f "$repo/flake.nix" ]; then \
            echo "Checking $repo..."; \
            (cd $repo && nix flake check --no-build); \
        else \
            echo "Skipping $repo (no flake.nix)"; \
        fi \
    done
    @echo "✅ Workspace check completed!"

# Build a package exported from the meta-workspace
build-pkg pkg_name:
    @echo "🚀 Building package: {{pkg_name}}..."
    @nix build .#{{pkg_name}}

# Run CI checks (wrapper for check-all)
ci: check-all

# Apply a global refactor across all repositories
# Usage: just refactor "search_regex" "replacement_string"
refactor search replace:
    @echo "🛠️ Applying global refactor..."
    @for repo in {{REPOS}}; do \
        echo "Processing $repo..."; \
        find $repo -maxdepth 3 -name "*.nix" -exec sed -i "s/{{search}}/{{replace}}/g" {} +; \
    done
    @echo "✅ Refactor applied to all submodules."

# --- Advanced Workspace Autonomy ---

# Create and checkout a new branch across the entire workspace
branch name:
    @echo "🌿 Creating branch '{{name}}' in all repositories..."
    @for repo in {{REPOS}}; do \
        git -C $repo checkout -b {{name}} 2>/dev/null || git -C $repo checkout {{name}}; \
    done
    @git checkout -b {{name}} 2>/dev/null || git checkout {{name}}
    @echo "✅ Branch '{{name}}' is now active everywhere."

# Search for a pattern across all files in the workspace (ignores .git)
find pattern:
    @echo "🔍 Searching for '{{pattern}}'..."
    @grep -rnE "{{pattern}}" . --exclude-dir=.git --exclude-dir=.devenv --exclude=flake.lock || echo "No matches found."

# --- Deployment ---

# Deploy to the entire fleet via Colmena
deploy-fleet:
    @echo "🚀 Deploying to entire fleet via Colmena..."
    colmena apply --flake .#colmena --impure

# Deploy only to AI Edge nodes (Orin + RPi)
deploy-edge:
    @echo "🚀 Sequential Edge Deployment..."
    @just deploy-orin
    @colmena apply --flake .#colmena --on rpi5-1,rpi5-2 --impure
    @echo "✅ Edge deployment complete."

# --- Live Updates ---

# Start a local instance of the dashboard for development
# Start a local instance of the dashboard for development
dev-dashboard:
    @echo "🚀 Starting Dashboard in Dev Mode..."
    @mkdir -p .dev-dashboard
    @echo "🔍 Generating Configuration..."
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard.config.services.homepage-dashboard.services | yq -P > .dev-dashboard/services.yaml
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard.config.services.homepage-dashboard.widgets | yq -P > .dev-dashboard/widgets.yaml
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard.config.services.homepage-dashboard.settings | yq -P > .dev-dashboard/settings.yaml
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard.config.services.homepage-dashboard.bookmarks | yq -P > .dev-dashboard/bookmarks.yaml
    @echo "🎨 Copying Custom CSS..."
    @rm -f .dev-dashboard/custom.css
    @cp -f nix-presets/containers/dashboard/homepage/custom.css .dev-dashboard/custom.css
    @echo "📦 Running Homepage Dashboard on http://localhost:8083..."
    @mkdir -p .dev-dashboard/cache
    @HOMEPAGE_CONFIG_DIR=$(pwd)/.dev-dashboard XDG_CACHE_HOME=$(pwd)/.dev-dashboard/cache PORT=8083 nix run nixpkgs#homepage-dashboard
# --- AI & Agentic Hub ---

# Sync AI documentation from workspace structure
ai-sync:
    @echo "🔄 Syncing Agentic Hub documentation..."
    @echo "# Workspace Discovery (Auto-generated)" > .agent/architecture.md
    @echo "Last Synced: $(date)" >> .agent/architecture.md
    @echo "" >> .agent/architecture.md
    @echo "## Structure: Meta-Repo (Modular Monorepo)" >> .agent/architecture.md
    @echo "This workspace is managed as a **Meta-repo**. It uses Git submodules to aggregate multiple independent flakes into a unified coding environment." >> .agent/architecture.md
    @echo "" >> .agent/architecture.md
    @echo "### Flake Hierarchy" >> .agent/architecture.md
    @echo '```mermaid' >> .agent/architecture.md
    @echo 'graph TD;' >> .agent/architecture.md
    @echo '    Meta[nix] -- Aggregates --> nix-config' >> .agent/architecture.md
    @for repo in {{REPOS}}; do \
        if [ "$repo" != "nix-config" ]; then \
            echo "    nix-config -- imports --> $repo" >> .agent/architecture.md; \
        fi \
    done
    @echo '```' >> .agent/architecture.md
    @echo "" >> .agent/architecture.md
    @echo "### Key Repositories" >> .agent/architecture.md
    @echo "| Repo | Role |" >> .agent/architecture.md
    @echo "| :--- | :--- |" >> .agent/architecture.md
    @echo "| **nix-config** | Primary system consumer / Host definitions |" >> .agent/architecture.md
    @echo "| **nix-presets** | Reusable service and desktop bundles |" >> .agent/architecture.md
    @echo "| **nix-hardware** | Device-specific configurations |" >> .agent/architecture.md
    @echo "✅ Documentation synced to .agent/architecture.md"

# Check health of AI services (Ollama, vLLM, MCP, etc.)
ai-check:
    @echo "--- AI Infrastructure Health ---"
    @curl -s http://localhost:11434/api/tags >/dev/null && echo "✅ Ollama (Local): Running" || echo "❌ Ollama (Local): Offline (Run 'just ai-up' to start)"
    @curl -s http://orin-nano.local:8000/v1/models >/dev/null && echo "✅ vLLM (Orin): Running" || echo "❌ vLLM (Orin): Offline"
    @if [ -f "${HOME}/.config/Claude/claude_desktop_config.json" ]; then \
        echo "✅ Claude MCP: Configured"; \
    else \
        echo "❌ Claude MCP: Missing Config"; \
    fi
    @echo "✅ Workspace Atlas Server: Ready"
    @btop --version > /dev/null 2>&1 && echo "✅ btop: Available (Observability)" || echo "⚠️  btop: Missing (Run in ai-shell)"
    @echo "---------------------------------"

# Comprehensive Fleet AI Probe
ai-health-fleet: 
    @echo "🔍 Probing AI Fleet Connectivity..."
    @printf "%-25s %-15s %-10s\n" "ENDPOINT" "SERVICE" "STATUS"
    @printf "%-25s %-15s %-10s\n" "-------------------------" "---------------" "----------"
    @curl -sk --connect-timeout 2 https://litellm.internal/health/readiness >/dev/null && printf "%-25s %-15s %-10s\n" "litellm.internal" "Gateway" "✅" || printf "%-25s %-15s %-10s\n" "litellm.internal" "Gateway" "❌"
    @curl -sk --connect-timeout 2 http://localhost:11434/api/tags >/dev/null && printf "%-25s %-15s %-10s\n" "localhost:11434" "Ollama" "✅" || printf "%-25s %-15s %-10s\n" "localhost:11434" "Ollama" "❌"
    @curl -sk --connect-timeout 2 http://10.85.46.104:8000/v1/models >/dev/null && printf "%-25s %-15s %-10s\n" "orin-nano (104)" "vLLM" "✅" || printf "%-25s %-15s %-10s\n" "orin-nano (104)" "vLLM" "❌"
    @curl -sk --connect-timeout 2 http://10.85.46.117:8000/v1/models >/dev/null && printf "%-25s %-15s %-10s\n" "rpi5-1 (117)" "vLLM" "✅" || printf "%-25s %-15s %-10s\n" "rpi5-1 (117)" "vLLM" "❌"
    @curl -sk --connect-timeout 2 https://openwebui.internal/health >/dev/null && printf "%-25s %-15s %-10s\n" "openwebui.internal" "WebUI" "✅" || printf "%-25s %-15s %-10s\n" "openwebui.internal" "WebUI" "❌"

# Enter the AI development shell
ai-shell:
    nix develop .#ai

# Semantic view of recent system errors (supports -m for machines, -u for units)
ai-logs *args:
    ./scripts/ai-logs.py {{args}}

# Specialized view for the AI Agent Team orchestration logs
ai-team-logs:
    ./scripts/ai-logs.py -m agent-team

# Rebuild the history index and sync missing items to the Antigravity UI
history:
    @echo "🔄 Synchronizing and rebuilding Antigravity history..."
    @chmod +x ./scripts/rebuild_history.py
    @./scripts/rebuild_history.py --sync
    @echo "✅ History rebuilt in conversation_history.md"
    @echo "💡 Tip: Restart Antigravity to see newly synced items in the sidebar."

# Distill conversation history into the permanent Knowledge Base (.agent/knowledge)
distill:
    @echo "🧠 Distilling conversation history into Knowledge Base..."
    @chmod +x ./scripts/rebuild_history.py
    @./scripts/rebuild_history.py --distill
    @echo "✅ Knowledge Items generated in .agent/knowledge/"

# [DEPRECATED] Use 'just mode playground' instead.
# Safely initialize the AI stack sequentially to prevent thermal overload
ai-init-safe:
    @echo "⚠️  This command is DEPRECATED. Use 'just mode playground' instead."
    @echo "❄️  Initializing AI Stack Safely (Sequential Pulls)..."
    @echo "Phase 1/4: Core AI Infrastructure (LiteLLM, Database)..."
    sudo systemctl start container@langfuse-db.service container@litellm.service ollama.service
    @echo "Phase 2/4: AI Designers (Langflow, ComfyUI)..."
    sudo systemctl start podman-langflow.service podman-comfyui.service
    @echo "   ...Waiting for container pulls to settle..."
    @sleep 10
    @echo "Phase 3/4: Application Layer (Open WebUI, Langfuse)..."
    sudo systemctl start container@open-webui.service container@langfuse.service

    @echo "Phase 4/4: Automation (n8n)..."
    sudo systemctl start container@n8n.service
    @echo "✅ AI Stack Initialization Triggered! Monitor with 'just ai-status'."

# --- AI Development (Aider Architect) ---

# Run Aider (The Architect) - Uses Gemini 2.0 Flash Thinking
architect:
    @cd nix-config && nix develop --command aider

# Run Aider with DeepSeek API (Fast Coding)
code:
    @cd nix-config && nix develop --command aider --model deepseek/deepseek-chat

# Run Aider with Gemini Pro (Deep Reasoning)
plan:
    @cd nix-config && nix develop --command aider --model gemini/gemini-2.0-flash-thinking-exp

# Run Aider LOCALLY (Free, Private, Uses Ollama via LiteLLM)
local:
    @OLLAMA_API_BASE=http://localhost:4000/v1 cd nix-config && nix develop --command aider \
      --model openai/qwen \
      --editor-model openai/qwen


# --- Distillation ---

# Distill recent changes or piped text into agent knowledge
ai-distill title="unnamed-session":
    @mkdir -p .agent/knowledge
    @if [ -t 0 ]; then \
        git diff @{u}..HEAD --stat > .agent/knowledge/$(date +%Y-%m-%d)-{{title}}.md; \
        echo "✅ Distilled git changes to .agent/knowledge/$(date +%Y-%m-%d)-{{title}}.md"; \
    else \
        cat > .agent/knowledge/$(date +%Y-%m-%d)-{{title}}.md; \
        echo "✅ Distilled piped content to .agent/knowledge/$(date +%Y-%m-%d)-{{title}}.md"; \
    fi

# --- Orin Nano Operations ---

# Check if the Orin Nano is reachable via mDNS
orin-ping:
    @ping -c 1 orin-nano.local >/dev/null 2>&1 && echo "✅ Orin Nano is Online (.local)" || echo "❌ Orin Nano is Offline"

# Deploy configuration to the Orin Nano (Builds locally, pushes to target)
deploy-orin: orin-ping
    @echo "🚀 Deploying to Orin Nano..."
    nixos-rebuild switch --flake .#orin-nano --target-host martin@orin-nano.local --build-host localhost --use-remote-sudo
    @echo "✅ Deployment complete. Don't forget to run 'just orin-seal' if this is a fresh install."

# Seal the TPM key on the Orin Nano (Run after first boot)
orin-seal:
    @echo "🔐 Sealing LUKS key to TPM..."
    ssh martin@orin-nano.local "sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2"

# Remote monitoring of Orin Nano performance
orin-status:
    @echo "📊 Remote Monitor (jtop)..."
    ssh -t martin@orin-nano.local "nix-shell -p jtop --run jtop"

# View logs for AI services on the Orin Nano
orin-logs service="vllm":
    @echo "📜 Viewing logs for {{service}}..."
    ssh martin@orin-nano.local "sudo podman logs -f {{service}}"

# Install NixOS on the Orin Nano (requires SSH access to any Linux on the device)
orin-install target="root@orin-nano.local":
    @echo "💾 Installing NixOS on Orin Nano via nixos-anywhere..."
    nix run github:nix-community/nixos-anywhere -- --flake .#orin-nano {{target}}

# Enter a remote shell on the Orin Nano
orin-shell:
    ssh martin@orin-nano.local
# --- Build Optimization (Cachix) ---

# Authenticate with Cachix (Run once)
cache-auth token:
    cachix authtoken {{token}}

# Enable a cache for use (Download binaries)
cache-use name="kleinbem":
    cachix use {{name}}

# Push current build results to your cache (Requires CACHIX_SIGNING_KEY in environment or SOPS)
cache-push name="kleinbem":
    @echo "📦 Pushing latest build results to {{name}}..."
    @if [ -n "$CACHIX_SIGNING_KEY" ]; then \
        nix build .#orin-nano --json | jq -r '.[].outputs | to_entries[].value' | cachix push {{name}}; \
    elif [ -f "nix-secrets/secrets.yaml" ]; then \
        sops exec-env nix-secrets/secrets.yaml "nix build .#orin-nano --json | jq -r '.[].outputs | to_entries[].value' | cachix push {{name}}"; \
    else \
        echo "❌ Error: CACHIX_SIGNING_KEY not found in environment and nix-secrets/secrets.yaml is missing."; \
        exit 1; \
    fi
# --- Personal Knowledge Management ---

# Quick capture a note to the Obsidian Inbox
capture message="":
    @./scripts/obsidian-capture.sh {{message}}

# Organize the Obsidian vault into a PARA structure
organize-notes:
    @chmod +x ./scripts/organize-notes.sh
    @./scripts/organize-notes.sh

# Run a health check on the Obsidian vault
vault-check:
    @chmod +x ./scripts/vault-health.sh
    @./scripts/vault-health.sh

# Link repository documentation into the Obsidian vault
link-docs:
    @chmod +x ./scripts/link-docs-to-obsidian.sh
    @./scripts/link-docs-to-obsidian.sh

# Open the Obsidian application
obsidian:
    @obsidian &

# --- Browser Maintenance ---

# Quickly reset the Firefox Developer Edition (laboratory) profile folder
reset-firefox-laboratory:
    @echo "🧹 Resetting Firefox Laboratory Profile..."
    rm -rf ~/.mozilla/firefox/laboratory
    @echo "✅ Profile directory cleared. It will be re-initialized on next launch."

# Clean up orphaned Zen and Firefox profile folders
clean-browsers:
    @echo "🧹 Cleaning up orphaned browser data..."
    rm -rf ~/.config/zen ~/.zen ~/.mozilla/firefox/*.dev-edition-default
    @echo "✅ Cleanup complete."
