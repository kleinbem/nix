---
description: "How to add a new NixOS host"
---

# Add a New Host

To introduce a new physical or virtual machine into the fleet:

1. Read `nix-config/hosts/AGENTS.md` for host-specific layout rules.
2. The host must be added to three primary locations:
   - `inventory.nix` (master source for infrastructure).
   - `flake.nix` (inside `nix-config/`).
3. You must create a `nix-hardware` module for the device.
4. Run `just maintenance::sync-agent` to update the system reference docs.
