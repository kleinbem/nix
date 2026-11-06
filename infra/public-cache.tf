# Public Nix binary cache (cache.kleinbem.dev) for kleinbem's open-source projects:
# static files in R2. Each project's CI pushes its main build with `nix copy`,
# lists it in roots/<repo> and deletes what no roots list mentions, so the bucket
# holds one build per project, inside R2's free 10 GB. Unrelated to Attic, which
# still answers on that name, hence public_cache_domain_live. R2 has no spending
# cap: tools/r2-budget.sh takes the domain offline past the budget. Signing key:
# `nix key generate-secret --key-name cache.kleinbem.dev-1` into infra/terraform.yaml;
# its public half goes in each project's nixConfig.

locals {
  public_cache_domain = "cache.kleinbem.dev"
  # false until Attic no longer answers on cache.kleinbem.dev (nix-config's
  # inventory and infra/netbird/dns.tf); then true attaches the domain.
  public_cache_domain_live = false

  public_cache_lifecycle = {
    rules = [{
      # Mirrors the default rule R2 gives every new bucket (PUT replaces it).
      id                              = "abort-multipart-7d"
      enabled                         = true
      conditions                      = { prefix = "" }
      abortMultipartUploadsTransition = { condition = { type = "Age", maxAge = 7 * 86400 } }
    }]
  }
}

# Was mesh-agents-cache (never public, always empty): the rename replaces it.
moved {
  from = cloudflare_r2_bucket.mesh_agents_cache
  to   = cloudflare_r2_bucket.public_cache
}

resource "cloudflare_r2_bucket" "public_cache" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-cache"
}

moved {
  from = terraform_data.mesh_agents_cache_bucket
  to   = terraform_data.public_cache_bucket
}

# The public custom domain and the lifecycle rules: v5-only resources in the
# provider, so via the API as for the backup bucket (cloudflare-r2.tf). The
# custom domain creates its own proxied DNS record in the zone. On replace or
# destroy, the old domain is detached first, so the old bucket can go.
resource "terraform_data" "public_cache_bucket" {
  triggers_replace = {
    bucket    = cloudflare_r2_bucket.public_cache.name
    domain    = local.public_cache_domain
    live      = local.public_cache_domain_live
    lifecycle = jsonencode(local.public_cache_lifecycle)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    environment = {
      CF_API_TOKEN  = var.cloudflare_api_token
      CF_ACCOUNT_ID = var.cloudflare_account_id
      ZONE_ID       = data.cloudflare_zone.main.id
      BUCKET        = cloudflare_r2_bucket.public_cache.name
      DOMAIN        = local.public_cache_domain
      LIVE          = local.public_cache_domain_live
      LIFECYCLE     = jsonencode(local.public_cache_lifecycle)
    }
    command = <<-EOT
      api="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets/$BUCKET"
      auth=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

      if [ "$LIVE" != true ]; then
        echo "$BUCKET: $DOMAIN not attached yet (public_cache_domain_live)"
      elif curl -fsS "$${auth[@]}" "$api/domains/custom" |
        jq -e --arg d "$DOMAIN" '.result.domains[] | select(.domain == $d)' >/dev/null; then
        echo "$BUCKET: $DOMAIN already attached"
      else
        curl -fsS -X POST "$${auth[@]}" "$api/domains/custom" \
          --data "$(jq -n --arg d "$DOMAIN" --arg z "$ZONE_ID" \
            '{domain: $d, zoneId: $z, enabled: true, minTLS: "1.2"}')" |
          jq -e '.success' >/dev/null
        echo "$BUCKET: $DOMAIN attached"
      fi

      curl -fsS -X PUT "$${auth[@]}" "$api/lifecycle" --data "$LIFECYCLE" | jq -e '.success' >/dev/null
      echo "$BUCKET: lifecycle rules applied"
    EOT
  }

  # Destroy provisioners see only self, so the credentials come from the
  # environment tools/tf-apply.sh sets up. Detaches every custom domain of
  # the old bucket (also the never-public mesh-agents-cache.kleinbem.dev).
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    environment = {
      BUCKET = self.triggers_replace.bucket
    }
    command = <<-EOT
      api="https://api.cloudflare.com/client/v4/accounts/$TF_VAR_cloudflare_account_id/r2/buckets/$BUCKET"
      auth=(-H "Authorization: Bearer $TF_VAR_cloudflare_api_token" -H "Content-Type: application/json")
      domains=$(curl -fsS "$${auth[@]}" "$api/domains/custom" | jq -r '.result.domains[].domain') || {
        echo "$BUCKET: gone or unreadable, nothing to detach"
        exit 0
      }
      for d in $domains; do
        curl -fsS -X DELETE "$${auth[@]}" "$api/domains/custom/$d" | jq -e '.success' >/dev/null
        echo "$BUCKET: $d detached"
      done
    EOT
  }
}

# Cloudflare doesn't cache .narinfo or nar/* by default. Store paths never change
# under a name, so cache 30 days at the edge, 404s for a minute so fresh pushes
# show up. A zone has one ruleset per phase: further cache rules go here.
resource "cloudflare_ruleset" "cache_settings" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Cache settings"
  description = "Cache rules for kleinbem.dev"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    description = "Public Nix binary cache: content-addressed, cache at the edge"
    expression  = "(http.host eq \"${local.public_cache_domain}\")"
    action      = "set_cache_settings"
    enabled     = true

    action_parameters {
      cache = true

      edge_ttl {
        mode    = "override_origin"
        default = 30 * 86400

        status_code_ttl {
          status_code = 404
          value       = 60
        }
      }

      browser_ttl {
        mode = "respect_origin"
      }
    }
  }
}
