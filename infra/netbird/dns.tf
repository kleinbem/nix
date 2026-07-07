# Mesh-internal DNS for the binary-cache entrypoint.
#
# cache.kleinbem.dev must resolve to core-pi's mesh IP for every NetBird peer
# (fleet hosts + ephemeral CI runners) so pulls and pushes traverse WireGuard
# instead of the public Cloudflare tunnel (whose 100 MiB per-NAR cap 413s big
# closures). History: this pointer was copy-pasted as /etc/hosts entries in
# three places (attic-pull.nix default, per-host overrides, the CI
# nix-fleet-setup action) — the caddy move to core-pi on 2026-07-06 left them
# all stale and took the cache offline fleet-wide (2026-07-07). This record is
# the single mesh-wide source of truth. The /etc/hosts entries stay in place
# as overrides until every peer is confirmed resolving via NetBird DNS
# (hosts files always win over DNS, so the rollout is safe in both
# directions); retire them after that.
#
# ZONE SCOPE is deliberately the single FQDN, NOT kleinbem.dev: NetBird
# answers its custom zones authoritatively, so a domain-wide zone would
# shadow the PUBLIC kleinbem.dev records (code., home., …) for mesh peers.

data "netbird_group" "all" {
  # NetBird's built-in group containing every peer.
  name = "All"
}

resource "netbird_dns_zone" "cache" {
  name                 = "cache-entrypoint"
  domain               = "cache.kleinbem.dev"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "cache" {
  zone_id = netbird_dns_zone.cache.id
  # Root of the single-FQDN zone.
  name = "cache.kleinbem.dev"
  type = "A"
  # Track the cache entrypoint peer (caddy + attic host) instead of
  # hardcoding — the data source already exists for the no-expiry flags.
  content = data.netbird_peer.no_expiry["core-pi"].ip
  ttl     = 300
}
