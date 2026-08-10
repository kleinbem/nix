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
