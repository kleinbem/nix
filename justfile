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

# Switch System (delegates to nix-config)
switch:
    cd nix-config && nh os switch .

# Switch System with Local Overrides
switch-local:
    cd nix-config && just switch-local

# Update All Flake Locks
update-all:
    nix flake update
    @for repo in {{REPOS}}; do (cd $repo && nix flake update); done

# --- Validation & Maintenance ---

# Format all nix code
fmt:
    @nix fmt *.nix 2>/dev/null || true
    @for repo in {{REPOS}}; do echo "Formatting $repo..."; (cd $repo && nix fmt); done

# Check all flakes for errors (evaluation only by default for speed)
check:
    @nix flake check --no-build
    @for repo in {{REPOS}}; do echo "Checking $repo..."; (cd $repo && nix flake check --no-build) || exit 1; done

# Run comprehensive checks across all repositories (shows warnings, continues on error)
diagnose:
    @echo "--- Diagnosing Workspace ---"
    @for repo in {{REPOS}} .; do \
        echo "\n🔍 Checking $$repo..."; \
        (cd $$repo && nix flake check --no-build --show-trace --all-systems 2>&1) || echo "⚠️  Check failed for $$repo"; \
    done

# Garbage collect all repositories
clean:
    nix-collect-garbage -d


