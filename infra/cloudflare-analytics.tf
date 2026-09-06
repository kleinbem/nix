# Cloudflare Web Analytics for kleinbem.dev.
#
# Privacy-preserving RUM: no cookies, no client-side state, no consent
# banner required. `auto_install = true` on an orange-clouded zone means
# Cloudflare injects the beacon at the edge into text/html responses — so
# there is NOTHING to add to kleinbem-site's HTML or the build chain.
#
# Scope note: the beacon is injected zone-wide (that's how orange-cloud
# auto-install works — `host`/gray-cloud is the only per-hostname mode and
# it can't auto-inject). In practice it only lands on the marketing site:
# login.kleinbem.dev serves JSON (no HTML to inject into) and
# vault.kleinbem.dev's CSP blocks the external beacon script. If that ever
# needs tightening, add a `cloudflare_web_analytics_rule` to restrict the
# ruleset to host "kleinbem.dev".
resource "cloudflare_web_analytics_site" "kleinbem_dev" {
  account_id   = var.cloudflare_account_id
  zone_tag     = data.cloudflare_zone.main.id
  auto_install = true
}

output "web_analytics_site_tag" {
  description = "Cloudflare Web Analytics site tag (identifies the site in the dashboard/API)."
  value       = cloudflare_web_analytics_site.kleinbem_dev.site_tag
}
