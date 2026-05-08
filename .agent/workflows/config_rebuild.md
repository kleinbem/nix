---
description: Apply the NixOS configuration to the current system
---

# Workflow: System Rebuild

1. Run Security Scan
   `.agent/scripts/secure-scan.sh`
   *(Check the generated report in `.agent/audit/`. Proceed only if safe.)*

2. Check if the flake is valid
   `nix flake check`

3. Rebuild and switch to the new configuration
   `sudo nixos-rebuild switch --flake .#$(hostname)`

// turbo
4. Check the status of the systemd units to ensure everything came up
   `systemctl list-units --failed`
