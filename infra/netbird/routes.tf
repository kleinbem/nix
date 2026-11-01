# Network routes: reach containers (which don't run NetBird) through a
# gateway peer. Access is gated by each route's `access_control_groups`, no
# netbird_policy needed. Provider v0.0.9 predates the network_* resources,
# so this uses netbird_route.

resource "netbird_route" "buzz_relay" {
  network_id  = "buzz-relay"
  description = "Buzz relay (Nostr chat/git/agent workspace) container on nixos-nvme. Narrow /32 — not the whole 10.85.46.0/24 container-bridge subnet — kept minimal on purpose, widen only if more containers there need mesh reachability."

  # 10.85.46.131 = myInventory.network.nodes.buzz.ip (nix-config/inventory.nix)
  network = "10.85.46.131/32"

  # A single peer, not peer_groups: the bridge address is only reachable on
  # nixos-nvme, not on other personal-devices peers.
  peer = data.netbird_peer.personal_devices["nixos-nvme"].id

  # Required by the schema even with `peer` set.
  groups = [netbird_group.personal_devices.id]

  # Personal devices, plus `cache` (core-pi): its Caddy fronts the relay as
  # buzz.kleinbem.dev (dns.tf).
  access_control_groups = [netbird_group.personal_devices.id, netbird_group.cache.id]

  # The container has no route back to the mesh CIDR, only its bridge.
  masquerade = true

  enabled = true
}

# ---------------------------------------------------------------------------
# Lets Caddy on core-pi reach the mesh-only services' backends, which sit on
# other hosts' host-local container bridges (Caddy 502s without these). Same
# pattern as buzz_relay: one /32 per container, pinned gateway, masqueraded.
# Only `cache` (core-pi) may use them; everyone else goes through Caddy.
# IPs must match nix-config/inventory.nix.

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

resource "netbird_route" "garage_ui" {
  network_id            = "garage-ui"
  description           = "garage-ui container on nixos-nvme (mesh-only, Authentik OIDC login)."
  network               = "10.85.46.134/32"
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

resource "netbird_route" "garage_s3" {
  network_id            = "garage-s3"
  description           = "Garage S3 object storage on nixos-nvme (cbr0 host-native service). Live IP 10.85.46.1:3900. Allows core-pi Caddy and mesh peers to reach S3 directly without Cloudflare 100MB cap."
  network               = "10.85.46.1/32"
  peer                  = data.netbird_peer.personal_devices["nixos-nvme"].id
  groups                = [netbird_group.personal_devices.id]
  access_control_groups = [netbird_group.cache.id, netbird_group.personal_devices.id]
  masquerade            = true
  enabled               = true
}

resource "netbird_route" "qbittorrent" {
  network_id            = "qbittorrent"
  description           = "qbittorrent container on nasbook (mesh-only service)."
  network               = "10.85.47.134/32"
  peer                  = data.netbird_peer.smart_home["nasbook"].id
  groups                = [netbird_group.smart_home.id]
  access_control_groups = [netbird_group.cache.id]
  masquerade            = true
  enabled               = true
}

