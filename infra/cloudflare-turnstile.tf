# Cloudflare Turnstile widget — bot protection for kleinbem-site's contact
# form, replacing/augmenting the honeypot field with a real challenge.
# Previously also covered kleinbem-auth's own /register page (decommissioned
# 2026-09-21 — self-registration moved to Authentik's own enrollment flow,
# which doesn't use Turnstile at all, see nix/infra/authentik.tf) — kept as
# a single-purpose widget now rather than repurposed.
#
# The sitekey is NOT a secret — Turnstile sitekeys are meant to ship in page
# source, same as the Cloudflare Web Analytics token (see
# cloudflare-analytics.tf). The `secret` attribute IS sensitive: it verifies
# challenge tokens server-side and must go through sops, not Terraform state
# or this repo — see kleinbem-site's contact function for how it's wired in
# once `tofu apply` has run.
#
# Requires: the token this root runs as needs "Account -> Turnstile -> Edit"
# added to its scope (same class of one-time manual token edit as Pages in
# cloudflare-pages.tf).
resource "cloudflare_turnstile_widget" "kleinbem_site" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-site"
  mode       = "managed"
  domains = [
    local.primary_domain,
    "www.${local.primary_domain}",
  ]
}

output "turnstile_site_key" {
  description = "Turnstile sitekey — not a secret, safe to embed client-side."
  value       = cloudflare_turnstile_widget.kleinbem_site.id
}

output "turnstile_secret_key" {
  description = "Turnstile secret key — sensitive. Read with `tofu output -raw turnstile_secret_key`, then sops --set it into kleinbem-secrets / `wrangler pages secret put` it — never paste it into chat or commit it."
  value       = cloudflare_turnstile_widget.kleinbem_site.secret
  sensitive   = true
}
