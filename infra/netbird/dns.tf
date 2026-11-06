# cache.kleinbem.dev resolves to the cache entrypoint's mesh IP for every peer,
# CI runners included (/etc/hosts pins from attic-pull.nix still win). Each zone
# is a single FQDN: NetBird answers its zones authoritatively, so a kleinbem.dev
# zone would hide the public records.

data "netbird_group" "all" {
  # NetBird's built-in group containing every peer.
  name = "All"
}

locals {
  cache_fqdn = "cache.kleinbem.dev"
}

resource "netbird_dns_zone" "cache" {
  name                 = "cache-entrypoint"
  domain               = local.cache_fqdn
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "cache" {
  zone_id = netbird_dns_zone.cache.id
  # Root of the single-FQDN zone.
  name = local.cache_fqdn
  type = "A"
  # The entrypoint peer (inventory.tf) must be in var.no_expiry_peers, since its
  # IP comes through that data source.
  content = data.netbird_peer.no_expiry[local.cache_entrypoint].ip
  ttl     = 300
}

# ---------------------------------------------------------------------------
# Mesh-only vhosts are not on the public tunnel, so peers resolve them to the
# entrypoint's mesh IP, which DNATs :443 to caddy. Same single-FQDN zones as above.
# ---------------------------------------------------------------------------
locals {
  # inventory.nix nodes with `meshOnly = true`; the cache keeps its own zone above.
  mesh_only_fqdns = [for d in local.inventory.mesh_only_fqdns : d if d != local.cache_fqdn]
}

resource "netbird_dns_zone" "mesh_only" {
  for_each             = toset(local.mesh_only_fqdns)
  name                 = "mesh-${replace(each.value, ".", "-")}"
  domain               = each.value
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "mesh_only" {
  for_each = netbird_dns_zone.mesh_only
  zone_id  = each.value.id
  name     = each.key
  type     = "A"
  content  = data.netbird_peer.no_expiry[local.cache_entrypoint].ip
  ttl      = 300
}
