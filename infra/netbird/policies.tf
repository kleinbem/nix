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
