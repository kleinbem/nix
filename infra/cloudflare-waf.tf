# ---------------------------------------------------------------------------
# Rate limit for the public, unauthenticated credential endpoints. The Free
# plan allows one rate-limit rule, so it guards the top target: Vaultwarden's
# token endpoint. On Pro, add n8n webhooks as a second rule.
# Needs "Zone WAF: Edit" on the token; a 403 on apply means that scope is missing.
# ---------------------------------------------------------------------------

resource "cloudflare_ruleset" "ratelimit" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Public credential-endpoint rate limits"
  description = "Throttle unauthenticated login/token endpoints on the tunnel"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules {
    ref         = "vault_token_bruteforce"
    description = "Vaultwarden /identity/connect/token — brute force / cred stuffing"
    expression  = "(http.host eq \"vault.kleinbem.dev\" and http.request.uri.path eq \"/identity/connect/token\")"
    action      = "block"

    ratelimit {
      # Per client IP, per Cloudflare PoP (cf.colo.id is required by the API).
      characteristics = ["ip.src", "cf.colo.id"]
      # Free plan allows only period = 10 and mitigation_timeout == period.
      # On Pro, raise to period 60 and mitigation_timeout 600.
      period              = 10
      requests_per_period = 20
      mitigation_timeout  = 10
    }
  }
}

# ---------------------------------------------------------------------------
# Custom rules have their own quota (5 on Free), separate from the rate limit.
# n8n's /webhook* paths skip Authentik on purpose (external callers can't log
# in; see authExcludePaths in nix-presets caddy). Real auth there is n8n's
# per-webhook Header Auth/HMAC; this only blocks obvious abuse, without
# guessing payload shape, so it can't break real webhook traffic.
# ---------------------------------------------------------------------------
resource "cloudflare_ruleset" "waf_custom" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Custom WAF rules"
  description = "Defense-in-depth for endpoints that can't require interactive auth"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    ref         = "n8n_webhook_abuse"
    description = "n8n webhooks — block known-bad IP reputation (real auth is n8n's own per-webhook Header Auth/HMAC)"
    expression  = "(http.host eq \"n8n.kleinbem.dev\" and starts_with(http.request.uri.path, \"/webhook\") and cf.threat_score gt 30)"
    action      = "block"
  }

  rules {
    ref         = "block_malicious_scanners"
    description = "Block known vulnerability scanners and automated exploit probes"
    expression  = "(http.user_agent contains \"sqlmap\" or http.user_agent contains \"nikto\" or http.user_agent contains \"masscan\" or http.user_agent contains \"acunetix\" or http.user_agent contains \"censys\")"
    action      = "block"
  }

  rules {
    ref         = "authentik_threat_challenge"
    description = "Managed challenge for high-threat IPs attempting Authentik login or API flows"
    expression  = "(http.host eq \"auth.kleinbem.dev\" and starts_with(http.request.uri.path, \"/api/v3/flows/executor/\") and cf.threat_score gt 20)"
    action      = "managed_challenge"
  }
}

