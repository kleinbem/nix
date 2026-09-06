# Fleet inventory bridge.
#
# nix-config/inventory.nix is the single source of truth for mesh group
# membership (its `meshGroups` attr). It's projected to JSON by
# nix-config/iac/data.nix and copied here by `../../tools/gen-iac-data.sh`
# (drift-guarded by `../../tools/check-iac-data.sh` + the `iac-data` flake
# check). Until 2026-09-07 these lists were hand-maintained `variable`
# defaults in groups.tf/peers.tf and silently drifted from the fleet.
#
# The `*_peers` variables below stay as explicit escape hatches (same
# pattern as imports.tf's id toggles) — set one to override the
# inventory-derived membership for a single apply; leave it null to track
# inventory.

locals {
  inventory = jsondecode(file("${path.module}/../inventory.json"))
  mesh      = local.inventory.mesh

  personal_device_peers = tolist(var.personal_device_peers != null ? var.personal_device_peers : local.mesh["personal-devices"])
  smart_home_peers      = tolist(var.smart_home_peers != null ? var.smart_home_peers : local.mesh["smart-home"])
  cache_peers           = tolist(var.cache_peers != null ? var.cache_peers : local.mesh["cache"])

  # The single caddy/attic entrypoint peer (the `central` host). dns.tf
  # points cache.kleinbem.dev + the mesh-only vhosts at this peer's mesh IP.
  cache_entrypoint = local.mesh.cache_entrypoint
}

variable "personal_device_peers" {
  type        = list(string)
  default     = null
  description = "Override for inventory.meshGroups.personal-devices (nix-config). Trusted machines allowed to SSH infra + use the buzz-relay route. null = track inventory."
}

variable "smart_home_peers" {
  type        = list(string)
  default     = null
  description = "Override for inventory.meshGroups.smart-home (nix-config). Automation nodes reachable over SSH from personal-devices. null = track inventory."
}

variable "cache_peers" {
  type        = list(string)
  default     = null
  description = "Override for inventory.meshGroups.cache (nix-config). The only destination CI runners may reach. null = track inventory."
}
