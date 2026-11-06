# Workspace Discovery (Auto-generated)
Last Synced: Thu 05 Mar 2026 19:46:47 GMT

## Structure: Conductor + Sibling Repos
`nix/` is a tooling-only conductor. The flakes are independent git+jj repos checked out as flat
siblings of `nix/` (not submodules); run repo commands inside the sibling you change.

### Flake Hierarchy
```mermaid
graph TD;
    Meta[nix] -- Aggregates --> nix-config
    nix-config -- imports --> nix-devshells
    nix-config -- imports --> nix-hardware
    nix-config -- imports --> nix-packages
    nix-config -- imports --> nix-presets
    nix-config -- imports --> kleinbem-secrets
    nix-config -- imports --> nix-templates
```

### Key Repositories
| Repo | Role |
| :--- | :--- |
| **nix-config** | Primary system consumer / Host definitions |
| **nix-presets** | Reusable service and desktop bundles |
| **nix-hardware** | Device-specific configurations |

## Workload Profiles (Specialisations)
The system supports multiple operational modes to balance performance and capability.
See the [Workload Profile Matrix](workload_profiles.md) for a detailed breakdown of services per mode.
