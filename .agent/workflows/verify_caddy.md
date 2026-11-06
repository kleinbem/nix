---
description: Verify Caddy service and dashboard accessibility
---

1. Apply the local configuration change from `nix/`:
   `just apply`

2. Check Caddy from `nix/`:
   `just in nix-config nixos::verify-caddy`

   It retries for about 10 seconds and exits non-zero when Caddy doesn't answer, printing the
   container's status and recent logs.

3. For more logs:
   `just in nix-config containers::logs caddy`
