---
description: Verify Caddy service and dashboard accessibility
---

Caddy runs as a container on core-pi (the `cache` host in `nix-config/inventory.nix`).
Commands run from `nix/` on the workstation.

1. Deploy the change to core-pi:
   `just apply core-pi`

2. Check the container there:
   `just in nix-config containers::status caddy core-pi`

3. Check the dashboard route through Caddy (IP and domain from `network.nodes.caddy` and
   `network.nodes.dashboard` in `inventory.nix`). Non-zero exit means it failed:
   `ssh core-pi curl -skf -o /dev/null --resolve home.kleinbem.dev:443:10.85.48.107 https://home.kleinbem.dev`

4. On failure, read the logs:
   `ssh core-pi journalctl -u container@caddy.service -n 50 --no-pager`

`just in nix-config nixos::verify-caddy` probes only the Caddy IP and its diagnostics read the
local host, so run it on core-pi itself.
