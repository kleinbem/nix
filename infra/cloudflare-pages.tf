# ---------------------------------------------------------------------------
# kleinbem-site (portfolio/blog) — served from Cloudflare Pages at
# www.kleinbem.dev, with the apex redirecting to it.
#
# Deliberately NOT at the apex (@) — that name is shared with the mail setup
# (MX/SPF/DKIM/DMARC/MTA-STS in cloudflare-dns.tf) and the wildcard tunnel
# CNAME (main.tf) that routes every other subdomain to core-pi. www.* is a
# brand-new name that touches none of that.
#
# The Pages *project* here has no build_config/source — kleinbem-site's own
# CI builds the site and pushes the built output via `wrangler pages deploy`
# (see .github/workflows/ci.yaml), so Cloudflare isn't also trying to run a
# second, competing build from a git integration.
#
# Requires: cloudflare_api_token (the existing one, used by this whole root)
# needs "Cloudflare Pages: Edit" added to its scope for `tofu apply` to manage
# these two resources. Separately, kleinbem-site's CI needs its own, narrower
# CLOUDFLARE_PAGES_DEPLOY_TOKEN (Cloudflare Pages: Edit only) — distributed
# via github-secrets.tf, not reused from this root's own token, so a leaked
# CI secret can't touch DNS/WAF/Zero Trust.
#
# NOTE on env vars/secrets: this resource used to also set
# deployment_configs.production.environment_variables/secrets
# (AUTHENTIK_CLIENT_ID/_SECRET, AUTH_SESSION_SECRET). That stopped working
# the moment kleinbem-site's own repo started shipping a wrangler.jsonc with
# pages_build_output_dir (the SvelteKit/adapter-cloudflare rewrite) —
# confirmed live 2026-09-22: once a Pages project has been deployed with a
# Wrangler config file present, Cloudflare treats that file as the deploy's
# source of truth and silently stops injecting dashboard/API-configured
# plaintext env vars, with no per-resource opt-out. (Root-caused after a
# live incident: /auth/login started redirecting with client_id=undefined;
# fixed at the time with a targeted `tofu apply
# -target=cloudflare_pages_project.kleinbem_site` to clear the stray
# build_config Cloudflare had written onto the project, but that only
# restores plaintext vars — it doesn't make deployment_configs a reliable
# delivery mechanism for a Wrangler-config-managed project going forward.)
#
# The working replacement, matching how Wrangler-config Pages projects are
# meant to receive config: non-secret values move into kleinbem-site's own
# wrangler.jsonc `vars` block (committed — AUTHENTIK_CLIENT_ID isn't
# sensitive, it's already visible in the outgoing OAuth redirect URL).
# Secrets are pushed by CI via `wrangler pages secret put` immediately
# before `wrangler pages deploy`, sourced from GitHub Actions secrets — see
# github-secrets.tf's kleinbem-site entry (AUTHENTIK_CLIENT_SECRET,
# AUTH_SESSION_SECRET, TURNSTILE_SECRET_KEY — RESEND_API_KEY deliberately
# left unwired, see github-secrets.tf's kleinbem-site comment) and
# kleinbem-site's ci.yaml for the push step. `wrangler pages secret put`
# binds at deploy time same as everything else on Pages, so CI running it
# every deploy (rather than a one-off manual `wrangler pages secret put`)
# keeps it in sync with rotations without drift.
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

# Apex (kleinbem.dev) keeps its existing CNAME to the tunnel (main.tf) — it's
# not removed, just no longer where a browser ends up. This redirect fires
# before that routing matters for a human visitor.
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
