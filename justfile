# Meta-Workspace Justfile
REPOS := "nix-config nix-devshells nix-hardware nix-presets nix-templates nix-packages"

default:
    @just --list

# --- Git Operations ---

# Show status of all repositories
status:
    @echo "--- Meta ---"
    @git status -s
    @for repo in {{REPOS}}; do echo "\n--- $repo ---"; git -C $repo status -s; done

# Pull changes in all repositories
pull:
    git pull
    @for repo in {{REPOS}}; do git -C $repo pull; done

# --- NixOS Operations ---

# Switch System (Defaults to Local Overrides for Workspace)
switch:
    @echo "🚀 Switching System (Local Workspace Mode)..."
    cd nix-config && just switch-local

# Switch System (Remote/Clean - Ignores local uncommitted changes in sub-repos)
switch-remote:
    cd nix-config && nh os switch .

# Boot System with Local Overrides (No Activation)
boot:
    cd nix-config && just boot-local

# Update All Flake Locks
update-all:
    nix flake update
    @for repo in {{REPOS}}; do (cd $repo && nix flake update); done

# --- Validation & Maintenance ---

# Format all nix code
fmt:
    @nix fmt *.nix 2>/dev/null || true
    @for repo in {{REPOS}}; do echo "Formatting $repo..."; (cd $repo && nix fmt); done

# Check NixOS Configuration (Skips DevShell check which fails in sandbox)
check:
    @echo "🔍 Checking NixOS Configuration..."
    @nix eval .#nixosConfigurations.nixos-nvme.config.system.build.toplevel.drvPath >/dev/null
    @echo "✅ Configuration is Valid!"

# Full verification: Run flake check on all workspace members
check-all: check
    @echo "🔍 Checking Workspace Repositories..."
    @for repo in {{REPOS}}; do echo "Checking $repo..."; (cd $repo && nix flake check --no-build); done
    @echo "✅ Workspace check completed!"

# Build a package exported from the meta-workspace
build-pkg pkg_name:
    @echo "🚀 Building package: {{pkg_name}}..."
    @nix build .#{{pkg_name}}

# --- Live Updates ---

# Start a local instance of the dashboard for development
# Start a local instance of the dashboard for development
dev-dashboard:
    @echo "🚀 Starting Dashboard in Dev Mode..."
    @mkdir -p .dev-dashboard
    @echo "🔍 Generating Configuration..."
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard-homepage.config.services.homepage-dashboard.services | yq -P > .dev-dashboard/services.yaml
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard-homepage.config.services.homepage-dashboard.widgets | yq -P > .dev-dashboard/widgets.yaml
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard-homepage.config.services.homepage-dashboard.settings | yq -P > .dev-dashboard/settings.yaml
    @nix eval --json --impure .#nixosConfigurations.nixos-nvme.config.containers.dashboard-homepage.config.services.homepage-dashboard.bookmarks | yq -P > .dev-dashboard/bookmarks.yaml
    @echo "🎨 Copying Custom CSS..."
    @rm -f .dev-dashboard/custom.css
    @cp -f nix-presets/containers/dashboard/homepage/custom.css .dev-dashboard/custom.css
    @echo "📦 Running Homepage Dashboard on http://localhost:8083..."
    @mkdir -p .dev-dashboard/cache
    @HOMEPAGE_CONFIG_DIR=$(pwd)/.dev-dashboard XDG_CACHE_HOME=$(pwd)/.dev-dashboard/cache PORT=8083 nix run nixpkgs#homepage-dashboard
