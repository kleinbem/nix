# NetBird groups. Peers self-register (data plane); this root manages the group
# objects AND their membership, resolved from peer NAMES via data lookups —
# empty groups made the ssh policy cosmetic, so membership is now declarative.
#
# Schema reconciled against provider v0.0.9: group = name (required) + optional
# peers (list of peer ids).

# Peer NAMES per group. Same contract as no_expiry_peers in peers.tf: the
# lookup FAILS on an absent or ambiguous name, so only list peers that
# CURRENTLY exist on the mesh (`just list-peers` to check).
variable "personal_device_peers" {
  type        = list(string)
  default     = ["nixos-nvme"]
  description = "Trusted-machine peer names (workstation, laptop; add phone once it is enrolled)."
}

variable "smart_home_peers" {
  type        = list(string)
  default     = ["hass-pi"]
  description = "Smart-home node peer names."
}

variable "cache_peers" {
  type        = list(string)
  default     = ["core-pi"]
  description = "Attic-cache entrypoint peer names — the only destination CI runners may reach."
}

data "netbird_peer" "personal_devices" {
  for_each = toset(var.personal_device_peers)
  name     = each.value
}

data "netbird_peer" "smart_home" {
  for_each = toset(var.smart_home_peers)
  name     = each.value
}

data "netbird_peer" "cache" {
  for_each = toset(var.cache_peers)
  name     = each.value
}

# Your trusted machines (workstation, laptop, phone) — the only peers allowed to
# SSH into infrastructure.
resource "netbird_group" "personal_devices" {
  name  = "personal-devices"
  peers = [for p in data.netbird_peer.personal_devices : p.id]
}

# Smart-home / automation nodes (hass-pi, future HA satellites).
resource "netbird_group" "smart_home" {
  name  = "smart-home"
  peers = [for p in data.netbird_peer.smart_home : p.id]
}

# The Attic cache entrypoint (core-pi fronts caddy/attic on :443 via the wt0
# DNAT). Destination group for the ci_to_attic policy in policies.tf.
resource "netbird_group" "cache" {
  name  = "cache"
  peers = [for p in data.netbird_peer.cache : p.id]
}

# Hosted CI runners (GitHub Actions). They enroll per-run via the EPHEMERAL
# setup key (see setup-keys.tf) and are auto-removed ~10 min after the run ends,
# so this group's membership is transient by design. Isolating them in their own
# group is what lets policy scope CI to ONLY the Attic cache peer — CI runners
# must never land in personal-devices (which can SSH infrastructure). See the
# `ci_to_attic` policy note in policies.tf.
resource "netbird_group" "ci_runners" {
  name = "ci-runners"
}
