---
description: Persistent memory of lessons learned and patterns to avoid
---

# Lessons Learned

## 1. Justfile Delegation

**Pattern**: When calling a child Justfile from a parent directory.

- ❌ **Bad**: `just -d path/to/child command` (Fails if `just` version differs or env logic differs).
- ✅ **Good**: `cd path/to/child && just command` (Robust, respects child's environment).

## 2. Flake Input Overrides (Direnv)

**Pattern**: Using a local copy of a private inputs (like `nix-secrets`) without polluting `flake.nix`.

- ❌ **Bad**: Changing `flake.nix` `url` to a local path (Breaks CI/Remote builds).
- ✅ **Good**: Use `.envrc` override:

    ```bash
    use flake . --override-input nix-secrets path:../nix-secrets
    ```

## 3. Filesystem Hierarchy Standard (FHS)

**Pattern**: Storing large stateful data (images, VMs).

- ❌ **Bad**: `/images` (Violates FHS, clutters root).
- ✅ **Good**: `/var/lib/images` (Standard, clean).

## 4. Absolute Paths in Modules

**Pattern**: Importing modules within the flake.

- ❌ **Bad**: `imports = [ ../../modules/foo.nix ]` (Fragile refactoring).
- ✅ **Good**: Pass `self` to specialArgs and use `"${self}/modules/foo.nix"` (Robust relocation).
