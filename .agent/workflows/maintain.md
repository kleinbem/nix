---
description: "Update flake inputs and clean up the system"
---

# System Maintenance

Keep the system performing well by running routine updates and cleaning up the Nix store.

## 1. Update All Dependencies
// turbo
Update the `flake.lock` files for all sub-repositories in the workspace.
```bash
just update-all
```

## 2. Verify Health
// turbo
Run formatting and flake checks to ensure no regressions were introduced.
```bash
just fmt
just check
```

## 3. Cleanup
// turbo
Remove old generations and garbage collect the Nix store to free up space.
```bash
just clean
```

## 4. System Optimization
// turbo
If you notice the store getting very large, you can run a manual optimization:
```bash
nix-store --optimise
```

## 5. Verify Disk Usage
// turbo
Check the disk space after cleanup to verify space reclaimed.
```bash
df -h /
```
