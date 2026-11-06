---
description: Verify Caddy service and dashboard accessibility
---

Caddy runs as a container on core-pi (the `cache` host in `nix-config/inventory.nix`).
Commands run from `nix/` on the workstation.

1. Deploy the change. Caddy is excluded from the nightly container update, so pull its new
   closure by hand once CI has published the manifest:
   - host config: `just apply core-pi`
   - Caddy itself: `just in nix-config containers::update caddy core-pi`. This restarts Caddy
     and briefly drops every route, so skip it when the change didn't touch Caddy.

2. Check the container there:
   `just in nix-config containers::status caddy core-pi`

3. Check the dashboard route and its certificate (IP and domain from `network.nodes.caddy`
   and `network.nodes.dashboard` in `inventory.nix`; core-pi keeps Caddy's root CA in
   `~/.pki/caddy-root.crt`). Non-zero exit means it failed:
   `ssh core-pi 'curl -sf -o /dev/null --cacert ~/.pki/caddy-root.crt --resolve home.kleinbem.dev:443:10.85.48.107 https://home.kleinbem.dev'`

4. On failure, read Caddy's own journal (forwarded to the host), and the container unit's for
   errors before Caddy started:
   `ssh core-pi journalctl -D /var/log/containers/caddy -u caddy.service -n 50 --no-pager`
   `ssh core-pi journalctl -u container@caddy.service -n 50 --no-pager`

`just in nix-config nixos::verify-caddy` probes only the Caddy IP and its diagnostics read the
local host, so run it on core-pi itself.
