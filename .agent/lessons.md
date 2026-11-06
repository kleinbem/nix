---
description: Persistent memory of lessons learned and patterns to avoid
---

# Lessons Learned

## 1. Justfile Delegation

**Pattern**: When calling a child Justfile from a parent directory.

- ❌ **Bad**: `just -d path/to/child command` (Fails if `just` version differs or env logic differs).
- ✅ **Good**: `cd path/to/child && just command` (Robust, respects child's environment).

## 2. Flake Input Overrides

**Pattern**: Using a local checkout of an input (like `kleinbem-secrets`) without polluting `flake.nix`.

- ❌ **Bad**: Changing `flake.nix` `url` to a local path (Breaks CI/Remote builds).
- ✅ **Good**: Pass `--override-input` to every command that evaluates the flake. In
  `nix-config`, the `just` recipes do this through `OVERRIDES` (`.just/common.just`), which
  covers every sibling checkout and `kleinbem-secrets`:

    ```bash
    nix build .#<attr> --override-input kleinbem-secrets git+file://$PWD/../kleinbem-secrets
    ```

  An override in `.envrc` (`use flake . --override-input ...`) only reaches the dev shell, not
  later `nix build` or deploy commands.

## 3. Filesystem Hierarchy Standard (FHS)

**Pattern**: Storing large stateful data (images, VMs).

- ❌ **Bad**: `/images` (Violates FHS, clutters root).
- ✅ **Good**: `/var/lib/images` (Standard, clean).

## 4. Absolute Paths in Modules

**Pattern**: Importing modules within the flake.

- ❌ **Bad**: `imports = [ ../../modules/foo.nix ]` (Fragile refactoring).
- ✅ **Good**: Pass `self` to specialArgs and use `"${self}/modules/foo.nix"` (Robust relocation).
