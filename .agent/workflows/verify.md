---
description: "Perform a dry-run build to verify configuration validity"
---

# Verify Configuration

Before switching to a new configuration, it is good practice to verify that your flakes are healthy and your code builds.

## 1. Check Flake Integrity
Run the flake check across all repositories to catch syntax errors or missing dependencies.

```bash
just check
```

## 2. Dry-Run Build
If you want to ensure the NixOS configuration builds without switching:

```bash
cd nix-config
nh os build . 
```
