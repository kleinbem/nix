# ---------------------------------------------------------------------------
# Cloudflare WAF — rate limiting for the unauthenticated credential endpoints
# that sit on the public tunnel. These are the only surfaces where an attacker
# can grind guesses at the edge before any app-level auth applies.
#
# Free plan gives ONE rate-limiting rule, so this is deliberately scoped to the
# single highest-value target: Vaultwarden's token endpoint (credential
# stuffing / master-password brute force). If you move to Pro (5 rules), the
# runner-up is login.kleinbem.dev's better-auth sign-in/sign-up POST — add a
# second `rules {}` block mirroring this one. The Access-gated (home) and
# mTLS-fronted (n8n, chat) hosts don't need this; cache/ntfy are lower value.
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
