# Network routes — advertise a private-network CIDR through a specific peer
# acting as gateway, for reaching things that don't run NetBird themselves
# (containers, in this case). This is the piece main.tf's own header comment
# had marked "(later)" — genuinely never built before 2026-08-10.
#
# Route access is gated by `access_control_groups` on the route resource
# itself, not a separate netbird_policy — NetBird treats "reach an external
# CIDR through a gateway peer" as distinct from peer-to-peer ACLs, so no
# additional policy resource is needed for this to work end-to-end.
#
# Resource/attribute names reconciled against the netbirdio/netbird provider
# docs at the pinned v0.0.9 tag (docs/resources/route.md) — this provider
# predates the newer network/network_router/network_resource resources, so
# `netbird_route` (the older, simpler API) is what's actually available here.

resource "netbird_route" "buzz_relay" {
  network_id  = "buzz-relay"
  description = "Buzz relay (Nostr chat/git/agent workspace) container on nixos-nvme. Narrow /32 — not the whole 10.85.46.0/24 container-bridge subnet — kept minimal on purpose, widen only if more containers there need mesh reachability."

  # 10.85.46.131 = myInventory.network.nodes.buzz.ip (nix-config/inventory.nix)
  network = "10.85.46.131/32"

  # nixos-nvme is the only peer that can actually reach this address (it's
  # a bridge address local to that host) — pin the single peer rather than
  # peer_groups, so NetBird never tries routing through mac-mini (also in
  # personal_devices) where this address isn't reachable at all.
  peer = data.netbird_peer.personal_devices["nixos-nvme"].id

  # Required by the schema regardless of `peer` being set (see both examples
  # in upstream's route.md) — reusing the existing personal-devices group
  # rather than introducing a new single-purpose one.
  groups = [netbird_group.personal_devices.id]

  # Who may actually USE this route: your own trusted machines only, same
  # group SSH access to smart-home is scoped to.
  access_control_groups = [netbird_group.personal_devices.id]

  # nixos-nvme must masquerade so return traffic looks like it came from
  # nixos-nvme itself — the buzz container has no route back to the NetBird
  # mesh CIDR (100.x.x.x) otherwise, only to its own bridge subnet.
  masquerade = true

  enabled = true
}

# ---------------------------------------------------------------------------
# Caddy reverse-proxy reachability for the mesh-only forward-auth services
# (code-server, syncthing, frigate, alertmanager, paperless — see
# dns.tf's mesh_only_fqdns). Added 2026-09-22: fixing the DNS forward
# (ai-hardening.nix) only got a client to auth.kleinbem.dev and back with a
# valid session — Caddy on core-pi then tries to reverse_proxy to each
# service's real backend IP, which lives on a DIFFERENT physical host's own
# container bridge (10.85.x.0/24, host-local, not mesh-routable by default).
# Confirmed live: none of these 5 ports were reachable from core-pi's own
# host network before this, despite being reachable locally on their own
# host — Caddy always 502'd once auth passed. Same buzz_relay pattern:
# narrow /32 per container, single pinned gateway peer, masqueraded.
#
# access_control_groups is deliberately `cache` (core-pi only, NOT
# personal_devices) — core-pi/Caddy is the only consumer of these routes;
# Martin's own devices reach these services the same way everyone else
# does, through auth.kleinbem.dev + Caddy, not by using the route directly.
#
# NOTE: code-server's and frigate's LIVE IPs below do not match what
# nix-config/inventory.nix currently declares (code-server: declared
# 10.85.46.101, live 10.85.46.22; frigate: declared 10.85.46.130, live
# 10.85.46.39) — confirmed via `machinectl status <name>` on nixos-nvme /
# orin-nano respectively. Routes point at the LIVE addresses (routing to
# the stale declared ones would reach nothing); the inventory.nix drift
# itself is a separate follow-up, not fixed here.

resource "netbird_route" "code_server" {
  network_id            = "code-server"
  description           = "code-server container on nixos-nvme (mesh-only forward-auth service). LIVE IP — see note above re: inventory.nix drift (declares .101)."
  network               = "10.85.46.22/32"
  peer                  = data.netbird_peer.personal_devices["nixos-nvme"].id
  groups                = [netbird_group.personal_devices.id]
  access_control_groups = [netbird_group.cache.id]
  masquerade            = true
  enabled               = true
}

resource "netbird_route" "syncthing" {
  network_id            = "syncthing"
  description           = "syncthing container on nixos-nvme (mesh-only forward-auth service)."
  network               = "10.85.46.127/32"
  peer                  = data.netbird_peer.personal_devices["nixos-nvme"].id
  groups                = [netbird_group.personal_devices.id]
  access_control_groups = [netbird_group.cache.id]
  masquerade            = true
  enabled               = true
}

resource "netbird_route" "frigate" {
  network_id            = "frigate"
  description           = "frigate container on orin-nano (mesh-only forward-auth service). LIVE IP — see note above re: inventory.nix drift (declares .130)."
  network               = "10.85.46.39/32"
  peer                  = data.netbird_peer.smart_home["orin-nano"].id
  groups                = [netbird_group.smart_home.id]
  access_control_groups = [netbird_group.cache.id]
  masquerade            = true
  enabled               = true
}

resource "netbird_route" "alertmanager" {
  network_id            = "alertmanager"
  description           = "alertmanager (part of the monitoring container) on mac-mini (mesh-only forward-auth service)."
  network               = "10.85.50.2/32"
  peer                  = data.netbird_peer.personal_devices["mac-mini"].id
  groups                = [netbird_group.personal_devices.id]
  access_control_groups = [netbird_group.cache.id]
  masquerade            = true
  enabled               = true
}

resource "netbird_route" "paperless" {
  network_id            = "paperless"
  description           = "paperless container on nasbook (mesh-only forward-auth service)."
  network               = "10.85.47.131/32"
  peer                  = data.netbird_peer.smart_home["nasbook"].id
  groups                = [netbird_group.smart_home.id]
  access_control_groups = [netbird_group.cache.id]
  masquerade            = true
  enabled               = true
}
