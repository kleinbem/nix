# Meta-Workspace Justfile
REPOS := `find . -maxdepth 1 -name "nix-*" -type d -printf "%f\n" | xargs echo`

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
    @echo "✅ Workspace cleaned."

# --- NixOS Operations ---

# Switch System (Defaults to Local Overrides for Workspace)
switch:
    @echo "🚀 Switching System (Root Workspace Mode)..."
    nh os switch . -- --impure

# Full Workspace Pulse: Stage, Update, Check, and Switch in one go.
apply: stage-all update-local check switch
    @echo "✨ Workspace applied and activated."

# Switch System (Remote/Clean - Ignores local uncommitted changes in sub-repos)
switch-remote:
    cd nix-config && nh os switch .

# Boot System with Local Overrides (No Activation)
boot:
    cd nix-config && just boot-local

update-all:
    #!/usr/bin/env bash
    DEVSHELLS_PATH="$(pwd)/nix-devshells"
    for repo in {{REPOS}}; do
        if [ -d "$repo" ] && [ -f "$repo/flake.nix" ]; then
            echo "Updating $repo..."
            (cd "$repo" && nix flake update --impure --override-input nix-devshells "path:$DEVSHELLS_PATH" --commit-lock-file 2>/dev/null) || \
            (cd "$repo" && nix flake update --impure --override-input nix-devshells "path:$DEVSHELLS_PATH")
        fi
    done
    echo "Updating ROOT..."
    nix flake update --impure
    echo "✅ All flakes upgraded."

# Update only local workspace flake inputs
update-local:
    @echo "🔄 Updating local workspace inputs..."
    nix flake lock --update-input nix-config \
                   --update-input nix-presets \
                   --update-input nix-hardware \
                   --update-input nix-packages \
                   --update-input nix-devshells \
                   --update-input nix-templates \
                   --update-input nix-secrets
    @echo "✅ Local inputs updated."

# --- Validation & Maintenance ---

# Format all nix code
fmt:
    @nix fmt *.nix 2>/dev/null || true
    @for repo in {{REPOS}}; do echo "Formatting $repo..."; (cd $repo && nix fmt); done

# Check NixOS Configuration (Skips DevShell check which fails in sandbox)
check:
    @echo "🔍 Checking NixOS Configuration..."
    @nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel.drvPath --impure >/dev/null
    @echo "✅ Configuration is Valid!"

# Dry Run System Activation
dry-run:
    @echo "🔍 Simulating NixOS Activation..."
    nixos-rebuild dry-activate --flake .#nixos-nvme

# Build and run a local VM of the system configuration
test-vm:
    @echo "🖥️ Building VM..."
    nixos-rebuild build-vm --flake .#nixos-nvme
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
    @glances --version > /dev/null 2>&1 && echo "✅ Glances: Available (Observability)" || echo "⚠️  Glances: Missing (Run in ai-shell)"
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

# Semantic view of recent system errors
ai-logs *args:
    ./scripts/ai-logs.py {{args}}

# Safely initialize the AI stack sequentially to prevent thermal overload
ai-init-safe:
    @echo "❄️  Initializing AI Stack Safely (Sequential Pulls)..."
    @echo "Phase 1/4: Core AI Infrastructure (LiteLLM, Database)..."
    sudo systemctl start podman-langfuse-db.service podman-litellm.service
    @echo "Phase 2/4: Langflow..."
    sudo systemctl start podman-langflow.service
    @echo "   ...Waiting for Langflow pull to settle..."
    @sleep 10
    @echo "Phase 3/4: ComfyUI (Large Image)..."
    sudo systemctl start --no-block podman-comfyui.service
    @echo "   ...Waiting for ComfyUI pull to start..."
    @sleep 10
    @echo "Phase 4/4: vLLM (Giant Image - 10GB+)..."
    sudo systemctl start --no-block podman-vllm.service
    @echo "✅ AI Stack Initialization Triggered! Monitor with 'just ai-check'."

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
