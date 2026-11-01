# Peer flags. This resource can't create peers (they self-register); it
# adopts an existing one by id and sets its control-plane flags.
#
# SSO-enrolled peers expire, and a headless server can't log in again without
# a browser; setup-key re-enrollment is refused for a registered peer. So
# infrastructure peers get login and inactivity expiration turned off here.
# The name lookup fails on absent or duplicate names: run `just list-peers` /
# `just prune-peers` first if plan errors here.

variable "no_expiry_peers" {
  type        = list(string)
  default     = ["core-pi", "nixos-nvme"]
  description = <<-EOT
    Names of SSO-enrolled infrastructure peers whose sessions must never
    expire. Only list peers that CURRENTLY exist in the account (the data
    lookup fails on absent names). hass-pi enrolls via setup key and is not
    subject to login expiration — leave it out. orin-nano / nasbook: currently
    off the mesh; re-enroll them first, then add them here.

    Hand-maintained on purpose (NOT inventory-derived): SSO- vs
    setup-key-enrollment is operational state, not fleet inventory. Must
    contain the inventory.meshGroups.cache host — dns.tf reads the cache
    entrypoint peer's IP through this data source.
  EOT
}

data "netbird_peer" "no_expiry" {
  for_each = toset(var.no_expiry_peers)
  name     = each.value
}

resource "netbird_peer" "no_expiry" {
  for_each                      = data.netbird_peer.no_expiry
  id                            = each.value.id
  login_expiration_enabled      = false
  inactivity_expiration_enabled = false

  # Pre-1.0 provider: do not risk a `destroy` deleting the live peer. Dropping
  # a peer from the list should be an explicit `tofu state rm`, never a destroy.
  lifecycle {
    prevent_destroy = true
  }
}
