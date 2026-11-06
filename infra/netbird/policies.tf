# Access policies. A group reaches another only if a policy allows it, and
# `netbird ssh` follows the same rules, so this is also the SSH gate. None of it
# means anything while NetBird's default All -> All policy exists (see below).

resource "netbird_policy" "ssh_personal_to_smart_home" {
  name        = "ssh-personal-to-smart-home"
  description = "Allow SSH from personal devices to smart-home nodes (e.g. netbird ssh hass-pi)."
  enabled     = true

  rule {
    name          = "ssh"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.smart_home.id]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["22"]
    action        = "accept"
  }
}

# Personal devices -> personal devices (workstation, tablet, phone, mac-mini).
# Required for running Herdr or dev shells from mobile devices into nixos-nvme.
resource "netbird_policy" "ssh_personal_to_personal" {
  name        = "ssh-personal-to-personal"
  description = "Allow SSH between trusted personal devices (e.g. tablet/phone to workstation for Herdr/dev)."
  enabled     = true

  rule {
    name          = "ssh"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.personal_devices.id]
    bidirectional = true
    protocol      = "tcp"
    ports         = ["22"]
    action        = "accept"
  }
}

# Personal devices -> personal devices ping/ICMP for mesh diagnostics.
resource "netbird_policy" "ping_personal_to_personal" {
  name        = "ping-personal-to-personal"
  description = "Allow ICMP ping between trusted personal devices for mesh diagnostics."
  enabled     = true

  rule {
    name          = "ping"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.personal_devices.id]
    bidirectional = true
    protocol      = "icmp"
    action        = "accept"
  }
}

# Personal devices -> personal devices TCP companion workflows:
# Weylus (1701), RDP (3389), DroidCam (4747), KDE Connect (1714:1764), Syncthing direct (22000).
resource "netbird_policy" "companion_tcp_personal_to_personal" {
  name        = "companion-tcp-personal-to-personal"
  description = "Allow TCP companion services (Weylus stylus/screen, RDP, DroidCam, KDE Connect, Syncthing) between trusted personal devices."
  enabled     = true

  rule {
    name          = "companion-tcp"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.personal_devices.id]
    bidirectional = true
    protocol      = "tcp"
    action        = "accept"
    port_ranges = [
      { start = 1701, end = 1701 },
      { start = 3389, end = 3389 },
      { start = 4747, end = 4747 },
      { start = 5555, end = 5555 },
      { start = 1714, end = 1764 },
      { start = 22000, end = 22000 },
    ]
  }
}

# Personal devices -> personal devices UDP companion workflows:
# KDE Connect discovery/pairing (1714:1764) and Syncthing transfer (22000).
resource "netbird_policy" "companion_udp_personal_to_personal" {
  name        = "companion-udp-personal-to-personal"
  description = "Allow UDP companion services (KDE Connect discovery, Syncthing transfer) between trusted personal devices."
  enabled     = true

  rule {
    name          = "companion-udp"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.personal_devices.id]
    bidirectional = true
    protocol      = "udp"
    action        = "accept"
    port_ranges = [
      { start = 1714, end = 1764 },
      { start = 22000, end = 22000 },
    ]
  }
}

# mac-mini's VictoriaMetrics scrapes node-exporter (9100) across the fleet.
resource "netbird_policy" "monitoring_scrape" {
  name        = "monitoring-scrape"
  description = "Allow monitoring host (mac-mini) to scrape Prometheus node-exporter (9100) across fleet nodes."
  enabled     = true

  rule {
    name    = "node-exporter"
    sources = [netbird_group.personal_devices.id]
    destinations = [
      netbird_group.personal_devices.id,
      netbird_group.smart_home.id,
      netbird_group.cache.id,
    ]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["9100"]
    action        = "accept"
  }
}
# --- The built-in "All -> All" default policy ---------------------------------
# While it exists every rule here is moot. It is closed with
# `just close-default-policy POLICY_ID`, not managed here: its live rule shape is
# unverified and a mismatched rule block would replace it. Every needed path
# must have its own policy first. To manage it later, once the shape is known:
#   variable "default_policy_id" { type = string, default = "" }
#   import {
#     for_each = var.default_policy_id == "" ? toset([]) : toset([var.default_policy_id])
#     to       = netbird_policy.default
#     id       = each.value
#   }
#   resource "netbird_policy" "default" {
#     name    = "Default"
#     enabled = false                 # disable rather than delete: reversible
#     rule { ... }                    # must match the live rule exactly
#     lifecycle { ignore_changes = [rule] }
#   }

# --- Fleet + CI runners -> Attic cache ------------------------------------------
# The cache is mesh-only, so without these, pulls and CI pushes fail once the
# default policy is gone. The `cache` group is core-pi (:443 on wt0 DNATs to
# caddy/attic). CI runners get the cache peer and nothing else.
resource "netbird_policy" "fleet_to_cache" {
  name        = "fleet-to-cache"
  description = "Allow trusted machines and smart-home nodes to pull from the Attic cache peer."
  enabled     = true

  rule {
    name = "cache-pull"
    sources = [
      netbird_group.personal_devices.id,
      netbird_group.smart_home.id,
    ]
    destinations  = [netbird_group.cache.id]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["443"]
    action        = "accept"
  }
}

resource "netbird_policy" "ci_to_attic" {
  name        = "ci-runners-to-attic"
  description = "Allow ephemeral CI runners to push to the Attic cache peer only."
  enabled     = true

  rule {
    name          = "attic-push"
    sources       = [netbird_group.ci_runners.id]
    destinations  = [netbird_group.cache.id]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["443"]
    action        = "accept"
  }
}

# Personal devices -> the Buzz relay (buzz_relay route in routes.tf). A route
# with access_control_groups only works through a policy whose destination is
# that group.
resource "netbird_policy" "personal_to_buzz_relay" {
  name        = "personal-to-buzz-relay"
  description = "Allow personal devices to reach the Buzz relay (3000) and its pairing relay (3001) via the buzz-relay route."
  enabled     = true

  rule {
    name          = "buzz-relay"
    sources       = [netbird_group.personal_devices.id]
    destinations  = [netbird_group.personal_devices.id]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["3000", "3001"]
    action        = "accept"
  }
}

# core-pi's Caddy -> the Buzz relay, for wss://buzz.kleinbem.dev (relay on 3000,
# pairing relay on 3001 at /pair).
resource "netbird_policy" "caddy_to_buzz_relay" {
  name        = "caddy-to-buzz-relay"
  description = "Allow core-pi's Caddy to reach the Buzz relay (3000) and its pairing relay (3001) via the buzz-relay route."
  enabled     = true

  rule {
    name          = "buzz-relay-proxy"
    sources       = [netbird_group.cache.id]
    destinations  = [netbird_group.cache.id]
    bidirectional = false
    protocol      = "tcp"
    ports         = ["3000", "3001"]
    action        = "accept"
  }
}
