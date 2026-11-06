# DNS-01 token so core-pi's Caddy gets Let's Encrypt certs for mesh-only names
# (inventory `publicCert = true`), for clients that only trust public CAs, like
# Buzz. The names still resolve only over NetBird.
# Zone Read is needed by caddy-dns/cloudflare to find the zone id.
resource "cloudflare_api_token" "caddy_acme_dns" {
  name = "caddy-acme-dns-core-pi"

  policies = [{
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    })
    effect = "allow"
    permission_groups = [{
      id = "DNS Write"
      }, {
      id = "Zone Read"
    }]
  }]
}

output "caddy_acme_dns_token" {
  description = "Cloudflare token for Caddy's DNS-01 challenge; synced into kleinbem-secrets/nix/per-host/core-pi.yaml by sync-secrets.sh."
  sensitive   = true
  value       = cloudflare_api_token.caddy_acme_dns.value
}
