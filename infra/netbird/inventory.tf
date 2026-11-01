# Mesh group membership comes from nix-config inventory.nix `meshGroups` via
# ../inventory.json (tools/gen-iac-data.sh, drift-checked by check-iac-data.sh).
# Set a `*_peers` variable to override one group for a single apply.

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
