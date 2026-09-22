# ---------------------------------------------------------------------------
# Cloudflare WAF — rate limiting for the unauthenticated credential endpoints
# that sit on the public tunnel. These are the only surfaces where an attacker
# can grind guesses at the edge before any app-level auth applies.
#
# Free plan gives ONE rate-limiting rule, so this is deliberately scoped to the
# single highest-value target: Vaultwarden's token endpoint (credential
# stuffing / master-password brute force). If you move to Pro (5 rules), the
# runner-up is n8n's webhook endpoints below (cloudflare_ruleset.waf_custom) —
# add a second `rules {}` block mirroring this one. The Access-gated (home)
# host doesn't need this; cache/ntfy are lower value.
#
# Requires: cloudflare_api_token with "Zone WAF: Edit" on kleinbem.dev. If
# `tofu apply` 403s here, that scope is missing from the token.
#
# Free-plan numeric limits are narrow and Cloudflare tweaks them: if apply is
# rejected for `period` / `mitigation_timeout`, snap them to the values the
# error names (typically period ∈ {10,60}, mitigation_timeout == period).
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
      # Free plan is entitled to period=10 only, and forces
      # mitigation_timeout == period ("not entitled to use the period 60,
      # can only use a period among [10]"). Net rule: >20 hits on the token
      # endpoint from one IP per 10s at a PoP → block that IP for 10s.
      # Coarser than the intended 20/60s + 10min block, but it's the free-plan
      # ceiling; on Pro bump period to 60 and mitigation_timeout to 600.
      period              = 10
      requests_per_period = 20
      mitigation_timeout  = 10
    }
  }
}

# ---------------------------------------------------------------------------
# Custom WAF rules (http_request_firewall_custom phase) — separate quota from
# rate-limiting above (5 rules on Free, not the 1-rule-limited ratelimit
# phase), so this doesn't compete with the Vaultwarden rule for the same slot.
#
# Scoped to n8n's /webhook* and /webhook-test* — these paths are
# DELIBERATELY unauthenticated at the network layer (external callers like
# GitHub/Stripe can't complete an interactive Authentik login redirect; see
# nix-presets/containers/caddy/helpers.nix's authExcludePaths and
# inventory.nix's n8n node). Real auth for these has to be n8n's own
# per-webhook Header Auth/HMAC verification (set per-workflow in n8n itself —
# not something this rule can check, it has no idea what a legitimate
# payload looks like). This is defense-in-depth underneath that, not a
# substitute for it: catches obvious abuse (known-bad IP reputation,
# oversized bodies) without guessing at payload shape, so it can't
# false-positive on real webhook traffic the way a method/header allowlist
# built without knowing the actual integrations would risk doing.
# ---------------------------------------------------------------------------
resource "cloudflare_ruleset" "waf_custom" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Custom WAF rules"
  description = "Defense-in-depth for endpoints that can't require interactive auth"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    ref         = "n8n_webhook_abuse"
    description = "n8n webhooks — block known-bad IP reputation or oversized bodies (real auth is n8n's own per-webhook Header Auth/HMAC)"
    expression  = "(http.host eq \"n8n.kleinbem.dev\" and starts_with(http.request.uri.path, \"/webhook\") and (cf.threat_score gt 30 or http.request.body.size gt 10485760))"
    action      = "block"
  }
}
