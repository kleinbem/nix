---
description: "How to update the NixOS system and repositories"
---

# Update System and Repositories

This workflow describes how to keep the meta-workspace and NixOS system up to date.

## 1. Pull Latest Changes
First, ensure all repositories are synced with remote.

```bash
just pull
```

## 2. Update Flake Inputs (Optional)
If you want to update dependencies (flake.lock) for all repositories:

```bash
just update-all
```

## 3. Apply NixOS Configuration
To switch the system to the current configuration in `nix-config`:

```bash
just switch
```
// turbo
Or if you are working with local overrides (e.g. `nix-secrets`):

```bash
just switch-local
```
