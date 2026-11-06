# NetBird groups and their membership. Peers self-register; membership is
# resolved from peer names in nix-config/inventory.nix `meshGroups` (see
# inventory.tf). The lookup fails on an absent or ambiguous name, so each
# name must match a peer on the mesh now (`just list-peers`).

data "netbird_peer" "personal_devices" {
  for_each = toset(local.personal_device_peers)
  name     = each.value
}

data "netbird_peer" "smart_home" {
  for_each = toset(local.smart_home_peers)
  name     = each.value
}

data "netbird_peer" "cache" {
  for_each = toset(local.cache_peers)
  name     = each.value
}

# sort(): the provider returns `peers` sorted by id while the comprehension
# runs in name order, so without it every plan shows a reorder.

# Your trusted machines (workstation, laptop, phone) — the only peers allowed to
# SSH into infrastructure.
resource "netbird_group" "personal_devices" {
  name  = "personal-devices"
  peers = sort([for p in data.netbird_peer.personal_devices : p.id])
}

# Smart-home / automation nodes (hass-pi, future HA satellites).
resource "netbird_group" "smart_home" {
  name  = "smart-home"
  peers = sort([for p in data.netbird_peer.smart_home : p.id])
}

# The Attic cache entrypoint (core-pi fronts caddy/attic on :443 via the wt0
# DNAT). Destination group for the ci_to_attic policy in policies.tf.
resource "netbird_group" "cache" {
  name  = "cache"
  peers = sort([for p in data.netbird_peer.cache : p.id])
}

# GitHub Actions runners, enrolled per run by the ephemeral setup key
# (setup-keys.tf) and removed ~10 min after. Their own group so ci_to_attic
# (policies.tf) can limit them to the cache peer. Membership is unmanaged.
resource "netbird_group" "ci_runners" {
  name = "ci-runners"
}

# Landing zone for hosts enrolled with the `hosts` setup key (setup-keys.tf).
# No policy references it, so a new host starts with no access; promote it
# via inventory.nix `meshGroups` once reviewed. Membership is unmanaged.
resource "netbird_group" "unclassified_hosts" {
  name = "unclassified-hosts"
}
