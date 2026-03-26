---
status: backlog
priority: medium
tags: [nixos, cosmic, desktop, nixpkgs, hash-mismatch, regression]
created: 2026-03-25
---
# ✏️ Mission: COSMIC Edit Restoration (Hash Fix)

**Objective:** Re-enable the `cosmic-edit` package in the system configuration once the upstream fixed-output derivation hash mismatch is resolved by the `nixos-cosmic` maintainers.

---

## 1. Current Workaround (Bypass)
The package is currently blocked because its fetcher encounters a checksum mismatch that cannot be resolved via local lock updates (upstream issue).
- **Overlay:** A dummy overlay `cosmic-edit = final.hello;` is active in `modules/nixos/common.nix` to prevent evaluation errors.
- **Environment:** The package is commented out in `modules/nixos/desktop.nix`.

## 2. Restoration Steps
Once the `nixos-cosmic` flake is updated with the correct hashes:
- [ ] **Remove Overlay:** Delete the `cosmic-edit = final.hello;` line from `common.nix`.
- [ ] **Uncomment Package:** Restore `cosmic-edit` to the `environment.systemPackages` list in `desktop.nix`.
- [ ] **Update Lock:** Run `nix flake update cosmic` in the `nix-config` directory.
- [ ] **Verify Build:** Run `nix build .#nixosConfigurations.nixos-nvme.config.system.build.toplevel --impure`.

## 3. Reference
- **Repo:** `lilyinstarlight/nixos-cosmic`
- **Issue Category:** Transitive source fetcher mismatch.
