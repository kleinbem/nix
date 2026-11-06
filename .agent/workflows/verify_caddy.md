---
description: Verify Caddy service and dashboard accessibility
---

Caddy runs as a container on core-pi (the `cache` host in `nix-config/inventory.nix`).
Commands run from `nix/` on the workstation.

1. Deploy the change to core-pi:
   `just apply core-pi`

2. Check the container there:
   `just in nix-config containers::status caddy core-pi`

3. Read its logs:
   `just in nix-config containers::logs caddy core-pi`

`just in nix-config nixos::verify-caddy` probes Caddy and fails after its retries, but its
diagnostics read the local host, so run it on core-pi itself.
