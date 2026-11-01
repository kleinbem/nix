# Turnstile bot protection for kleinbem-site's contact form. The secret goes
# to kleinbem-site's CI via github-secrets.tf, which writes it to Pages.
# The root's token needs "Account -> Turnstile -> Edit".
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
