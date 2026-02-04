# Architecture & Dependency Graph

This document explains the relationship between the repositories in this meta-workspace.

## Component Graph

```mermaid
graph TD;
    subgraph Meta
        Nix[nix] --> Config[nix-config]
    end

    subgraph Dependency Layers
        Config --> Hardware[nix-hardware]
        Config --> Presets[nix-presets]
        Config --> Packages[nix-packages]
        Config --> Secrets[nix-secrets]
        Config --> Templates[nix-templates]
        Config --> DevShells[nix-devshells]
    end

    subgraph External Inputs
        Config --> Nixpkgs[nixpkgs (unstable)]
        Config --> HM[home-manager]
        Config --> Nixpak[nixpak]
    end
```

## Repository Roles

| Repository | Role | Imported By |
| :--- | :--- | :--- |
| **nix-config** | The "Consumer". Aggregates everything into final `nixosConfigurations`. | `nix` (conceptually), Users |
| **nix-hardware** | Hardware-specific settings (file systems, boot loaders, kernel modules). | `nix-config` (hosts) |
| **nix-presets** | "Role" bundles (e.g. `gaming`, `work`). | `nix-config` (hosts/users) |
| **nix-packages** | Overlay for custom packages/versions. | `nix-config` (pkgs overlay) |
| **nix-devshells** | Standardized development environments. | `nix-config` (devShells) |
| **nix-secrets** | Private encrypted secrets (sops). | `nix-config` (modules) |

## Data Flow
1.  **Inputs**: `flake.nix` in `nix-config` pulls in all other local flakes as inputs.
2.  **Modules**: Specialized logic lives in `nix-presets` or `nix-hardware`.
3.  **Assembly**: `nix-config/hosts/<hostname>` imports specific modules and hardware profiles to build the system.
