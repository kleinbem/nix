---
description: "Update flake inputs and clean up the system"
---

# System Maintenance
// turbo-all


Keep the system performing well by running routine updates and cleaning up the Nix store.

## 1. Update All Dependencies
// turbo
Update the `flake.lock` files for all sub-repositories in the workspace.
```bash
# mcp_workspace-atlas_run_just_recipe --recipe "update-all"
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
# mcp_workspace-atlas_run_just_recipe --recipe "clean"
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

## 6. Final Health Check
// turbo
Ensure all services are still healthy after maintenance.
```bash
# mcp_workspace-atlas_check_ai_stack_health
# mcp_workspace-atlas_update_todo --task "Run system maintenance" --status "done"
```
