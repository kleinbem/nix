# Nix Meta-Workspace

This repository serves as the **entry point** and **conductor** for the federated Nix workspace. It ties together several specialized repositories to create a cohesive development environment.

## 📂 Structure

- **`nix-config`**: The core NixOS configurations, hosts, and secrets. **Start here.**
- **`nix-hardware`**: Reusable hardware-specific modules (e.g., NVMe tweaks, GPU config).
- **`nix-presets`**: Shared, generic modules (apps, containers, services) usable by any host.
- **`nix-devshells`**: Shared development shells and tools (includes `just`, `gh`, `lazygit`).
- **`nix-packages`**: Custom packages (NUR-style).
- **`nix-templates`**: Scaffolding for new projects and modules.

## 🚀 Getting Started

1.  **Enter the Workspace**:
    ```bash
    nix develop  # Pure fallback
    # OR
    direnv allow # Professional recommendation
    ```
    This loads `just`, `devenv`, `lazygit`, and the specialized AI-stack shell.

2.  **Verify Workspace Health**:
    ```bash
    workspace-status
    ```
    This custom command checks the availability of your AI services (Ollama, etc.).

3.  **Manage Services**:
    ```bash
    devenv up     # Starts background services
    devenv tasks  # Lists diagnostic tasks
    ```

4.  **Deploy System**:
    ```bash
    just switch
    ```
    *(Syncs your terminal, IDE settings, and Code-Server containers globally).*

## 🛠 Maintenance

Keep your workspace healthy with these commands:

- **Linting**: `just lint` (Check for dead code and style issues)
- **Fixing**: `just fix` (Auto-fix lints and format all code)
- **Updating**: `just update-all` (Update all flake inputs across the workspace)
- **Cleaning**: `just clean` (Remove temporary files and stale hooks)

## 🛠 Workflow

- **Environment Mobility**: You can `cd` into any sub-repository (e.g., `nix-config`). Your environment and tools follow you automatically.
- **Unified Settings**: Global IDE settings are managed in `nix-presets/code-common/settings.nix`.
- **System Control**: Use `just --help` to see all automated maintenance recipes.
