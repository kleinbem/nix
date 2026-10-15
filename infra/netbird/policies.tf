# Access policies. `netbird ssh` rides these access rules — a source group can
# reach a destination group only if a policy permits it — so this is the SSH
# gate for the keyless `netbird ssh hass-pi` path (server enabled host-side via
# my.services.netbird.allowServerSsh).
#
# IMPORTANT: NetBird ships a default "All → All" policy. Codify its removal /
# narrowing here (or in the console) — otherwise every peer, including the
# persona fleet, can already reach hass-pi regardless of the rule below.
#
# Schema reconciled against provider v0.0.9: `rule` is a list-nested block with
# sources/destinations (group-id lists), protocol, ports, bidirectional, action.

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

# Mac-mini (monitoring container) -> fleet Prometheus node-exporter scraping (9100).
# REQUIRED before closing the default All->All policy: without this, VictoriaMetrics
# on mac-mini cannot scrape node-exporter metrics across the fleet.
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
#
# Until this is removed, the SSH gate above is COSMETIC: NetBird ships a default
# policy that lets every peer reach every other peer, so anything enrolled
# (including the persona fleet) can already reach hass-pi regardless of the
# explicit rule. Closing it is the point of this whole root.
#
# It is handled OUT-OF-BAND (via `just close-default-policy`) rather than as a
# managed resource here, deliberately:
#   - The default policy is a tenant-specific object whose exact rule schema
#     (the "All" group id, bidirectional/protocol defaults) we have NOT verified
#     against the live API. Blind-writing a `rule {}` block risks a plan that
#     destroys/recreates the live policy — exactly the overconfidence we said we
#     would avoid. `just close-default-policy` deletes it via the API after
#     showing you what it found, and is reversible (recreate an All->All in the
#     console if a path breaks).
#
# PROMOTE TO DECLARATIVE LATER: once `just schema` + `just ids` confirm the live
# shape with the token, replace the recipe with an imported, managed resource
# here so the closure is enforced by `tofu plan`. Sketch:
#
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

# --- CI runners -> Attic cache (REQUIRED before closing the default policy) ----
#
# LANDMINE: the hosted-CI Attic offload (runners pushing >100 MiB NARs over the
# NetBird tunnel) works TODAY only because the default All->All policy lets the
# ephemeral CI peers reach the Attic peer. The moment you run
# `just close-default-policy`, that path dies unless THIS explicit rule exists.
# Add it (uncomment + apply) BEFORE closing the default, or CI build-all goes red
# with a 413 fallback. ci-runners must reach ONLY the cache peer — nothing else.
#
# The `cache` group (groups.tf) holds core-pi — the wt0 DNAT on :443 fronts
# caddy/attic there. The CI route target is the cache peer's NetBird IP (see
# nix-fleet-setup action).
# The fleet's own cache access. Without this, closing the default policy
# breaks nixos-nvme (dnsmasq resolves cache.kleinbem.dev to core-pi's MESH ip,
# so workstation pulls ride wt0) and hass-pi (autoUpgrade requireCache probes +
# substitution over the mesh) — not just CI.
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
# with access_control_groups is only usable through a policy whose
# destination is that group, and peers only connect to the routing peer
# (nixos-nvme) via such a policy. The route predates closing the default
# All->All policy and silently relied on it until this existed.
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
