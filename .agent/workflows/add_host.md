---
description: "How to add a new NixOS host"
---

# Add a New Host

To introduce a new physical or virtual machine into the fleet:

1. Read `nix-config/hosts/AGENTS.md` for host-specific layout rules.
2. Follow its checklist: `inventory.nix`, `hosts/<name>/`, a `nix-hardware` module, and
   `nixosConfigurations` in `modules/flake/hosts.nix`.
3. In `nix-config`, run `just dev::sync-agent` and `just dev::check-hosts`.
