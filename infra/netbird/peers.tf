# Peer FLAGS, managed as code. Peers themselves still self-register (data
# plane — `netbird up`; see the boundary note in main.tf), and this resource
# cannot create one: it adopts an existing peer by id and manages its mutable
# control-plane flags only.
#
# Why this exists: login expiration applies to SSO-enrolled peers, and a
# headless server cannot "log in once more" without a human and a browser.
# That is exactly how core-pi silently dropped off the mesh (2026-07-05:
# expired peer login → attic container unreachable → cache.kleinbem.dev 502 +
# CI pushes dead). Setup-key re-enrollment is REFUSED for an already-registered
# peer, so recovery needed an interactive `netbird up` device-code login on the
# host. Infrastructure peers therefore get login (and inactivity) expiration
# turned OFF here, so `tofu plan` flags any console drift.
#
# Schema reconciled against provider v0.0.9: resource `netbird_peer` takes a
# required `id` plus optional flags; data source `netbird_peer` looks up by
# `name`. The lookup FAILS if the name is absent or ambiguous — dns labels like
# nixos-nvme-212-232 hint at past name collisions, so if plan errors here run
# `just list-peers` / `just prune-peers` and reconcile first.

variable "no_expiry_peers" {
  type        = list(string)
  default     = ["core-pi", "nixos-nvme"]
  description = <<-EOT
    Names of SSO-enrolled infrastructure peers whose sessions must never
    expire. Only list peers that CURRENTLY exist in the account (the data
    lookup fails on absent names). hass-pi enrolls via setup key and is not
    subject to login expiration — leave it out. orin-nano / nasbook: currently
    off the mesh; re-enroll them first, then add them here.
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
