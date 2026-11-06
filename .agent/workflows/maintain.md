---
description: "Update flake inputs and clean up the system"
---

# System Maintenance

Routine updates and Nix store cleanup. Commands run from `nix/`.

## 1. Update Dependencies
CI opens `flake.lock` update PRs on its own. To align the local sub-flakes' lockfiles:
```bash
just maintenance::update-local
```
It stages the changes and never commits.

## 2. Verify Health
```bash
just maintenance::format-all
just check
```

## 3. Cleanup
Delete old generations and garbage-collect the store (asks for confirmation):
```bash
just maintenance::clean-all
```

## 4. Verify Disk Usage
```bash
df -h /
```

## 5. Final Health Check
```bash
systemctl list-units --failed --no-legend
```
Any output is a failed unit to look at.
