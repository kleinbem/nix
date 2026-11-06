# kleinbem-site on Cloudflare Pages at www.kleinbem.dev; the apex carries the
# mail records and tunnel CNAME, so it only redirects. kleinbem-site's CI
# builds and deploys with wrangler, so no build_config here. No vars either:
# with a wrangler.jsonc Cloudflare ignores API-set vars, and CI puts the
# secrets (github-secrets.tf) with `wrangler pages secret put`.

resource "cloudflare_pages_project" "kleinbem_site" {
  account_id        = var.cloudflare_account_id
  name              = "kleinbem-site"
  production_branch = "main"

  # Holds the secrets CI puts with wrangler; v5 would overwrite them.
  lifecycle {
    ignore_changes = [deployment_configs]
  }
}

resource "cloudflare_pages_domain" "kleinbem_site_www" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.kleinbem_site.name
  name         = "www.${local.primary_domain}"
}

# The apex keeps its tunnel CNAME (main.tf); this redirect runs first.
resource "cloudflare_ruleset" "apex_to_www" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Apex to www redirect"
  description = "kleinbem.dev -> www.kleinbem.dev (site now lives on Cloudflare Pages)"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [
    {
      ref         = "apex_to_www"
      description = "Redirect bare kleinbem.dev to www.kleinbem.dev, preserving path + query"
      expression  = "(http.host eq \"${local.primary_domain}\")"
      action      = "redirect"
      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = true
          target_url = {
            expression = "concat(\"https://www.${local.primary_domain}\", http.request.uri.path)"
          }
        }
      }
    }
  ]
}

resource "cloudflare_dns_record" "kleinbem_site_www" {
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  type    = "CNAME"
  content = "${cloudflare_pages_project.kleinbem_site.name}.pages.dev"
  proxied = true
  ttl     = 1
}

moved {
  from = cloudflare_record.kleinbem_site_www
  to   = cloudflare_dns_record.kleinbem_site_www
}
