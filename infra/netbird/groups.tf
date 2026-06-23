# NetBird groups. Peers are placed into groups either by a setup key's
# auto-assignment (see setup-keys.tf) or in the console; this root defines the
# group objects + intent, not peer membership lists (peers self-register).
#
# Schema reconciled against provider v0.0.9: group = name (required) + optional
# peers (list of peer ids).

# Your trusted machines (workstation, laptop, phone) — the only peers allowed to
# SSH into infrastructure. Add existing peers here, or in the console, by id.
resource "netbird_group" "personal_devices" {
  name = "personal-devices"
  # peers = [data.netbird_peer.nixos_nvme.id, ...]  # optional explicit membership
}

# Smart-home / automation nodes (hass-pi, future HA satellites). hass-pi lands
# here via the setup key's auto-assigned group on enrollment.
resource "netbird_group" "smart_home" {
  name = "smart-home"
}
