# ---------------------------------------------------------------------------
# kleinbem-site (portfolio/blog) — served from Cloudflare Pages at
# www.kleinbem.dev, with the apex redirecting to it.
#
# Not at the apex: that name carries the mail records (cloudflare-dns.tf) and
# the tunnel CNAME (main.tf).
#
# No build_config/source: kleinbem-site's CI builds and runs
# `wrangler pages deploy`. CI uses its own CLOUDFLARE_PAGES_DEPLOY_TOKEN
# (Pages: Edit only, from github-secrets.tf); this root's token needs
# "Cloudflare Pages: Edit" too.
#
# No env vars or secrets here: once a project deploys with a wrangler.jsonc,
# Cloudflare ignores API-set vars. Plain vars live in kleinbem-site's
# wrangler.jsonc; CI runs `wrangler pages secret put` before every deploy,
# from the GitHub secrets in github-secrets.tf.
# ---------------------------------------------------------------------------

resource "cloudflare_pages_project" "kleinbem_site" {
  account_id        = var.cloudflare_account_id
  name              = "kleinbem-site"
  production_branch = "main"
}

resource "cloudflare_pages_domain" "kleinbem_site_www" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.kleinbem_site.name
  domain       = "www.${local.primary_domain}"
}

resource "cloudflare_record" "kleinbem_site_www" {
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  type    = "CNAME"
  content = "${cloudflare_pages_project.kleinbem_site.name}.pages.dev"
  proxied = true
}

# The apex keeps its tunnel CNAME (main.tf); this redirect runs first.
resource "cloudflare_ruleset" "apex_to_www" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Apex to www redirect"
  description = "kleinbem.dev -> www.kleinbem.dev (site now lives on Cloudflare Pages)"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    ref         = "apex_to_www"
    description = "Redirect bare kleinbem.dev to www.kleinbem.dev, preserving path + query"
    expression  = "(http.host eq \"${local.primary_domain}\")"
    action      = "redirect"

    action_parameters {
      from_value {
        status_code = 301
        target_url {
          expression = "concat(\"https://www.${local.primary_domain}\", http.request.uri.path)"
        }
        preserve_query_string = true
      }
    }
  }
}
