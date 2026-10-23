# DNS-01 token for Caddy on core-pi (nix-presets containers/caddy, nodes with
# `publicCert = true` in nix-config/inventory.nix). Lets Caddy get publicly
# trusted Let's Encrypt certificates for mesh-only names such as
# buzz.kleinbem.dev without exposing them: the challenge is a TXT record, the
# name itself only resolves over NetBird (../netbird/dns.tf).
#
# Needed because some clients trust only the public CA list, not the fleet's
# Caddy local CA: Buzz 1.0 joins communities only over TLS and its websocket
# uses webpki-roots (block/buzz-app src-tauri/Cargo.toml).
#
# Scope: DNS edit + zone read on kleinbem.dev only. Zone read is what
# caddy-dns/cloudflare needs to find the zone id.
resource "cloudflare_api_token" "caddy_acme_dns" {
  name = "caddy-acme-dns-core-pi"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["Zone Read"],
      data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    }
  }
}

output "caddy_acme_dns_token" {
  description = "Cloudflare token for Caddy's DNS-01 challenge; synced into kleinbem-secrets/nix/per-host/core-pi.yaml by sync-secrets.sh."
  sensitive   = true
  value       = cloudflare_api_token.caddy_acme_dns.value
}
