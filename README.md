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
    nix develop
    ```
    This loads `just`, `lazygit`, and `gh`.

2.  **Verify Status**:
    ```bash
    just status
    ```

3.  **Deploy System**:
    ```bash
    just switch-local
    ```
    *(Delegates to `nix-config` using local repository overrides)*

## 🛠 Workflow

- **Edit Configuration**: Go to `nix-config`.
- **Add New Hardware**: Edit `nix-hardware`, then update `nix-config`'s lockfile.
- **Update All**: Run `just update-all` in this directory to update lockfiles in all sub-repos.
