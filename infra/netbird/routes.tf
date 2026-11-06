# Network routes: reach containers (which don't run NetBird) through a
# gateway peer. Traffic also needs a netbird_policy whose destination is the
# route's `access_control_groups` (policies.tf). These are legacy routes; the
# provider's netbird_network* resources would replace them, which recreates
# every route.

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

# Caddy on core-pi reaches the other hosts' container backends over the LAN
# routes in nix-config modules/nixos/network-routing.nix, not over NetBird.

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
