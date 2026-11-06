# The Free plan allows one rate-limit rule, so it guards the top target:
# Vaultwarden's token endpoint. Needs "Zone WAF: Edit" (403 on apply if missing).

resource "cloudflare_ruleset" "ratelimit" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Public credential-endpoint rate limits"
  description = "Throttle unauthenticated login/token endpoints on the tunnel"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "vault_token_bruteforce"
      description = "Vaultwarden /identity/connect/token — brute force / cred stuffing"
      expression  = "(http.host eq \"vault.kleinbem.dev\" and http.request.uri.path eq \"/identity/connect/token\")"
      action      = "block"
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 20
        mitigation_timeout  = 10
      }
    }
  ]
}

# Custom rules have their own quota (5 on Free). No threat-score rules: Cloudflare
# reports cf.threat_score as 0 now, so they never match.
# https://developers.cloudflare.com/ruleset-engine/rules-language/fields/reference/cf.threat_score/
resource "cloudflare_ruleset" "waf_custom" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Custom WAF rules"
  description = "Defense-in-depth for endpoints that can't require interactive auth"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      ref         = "block_malicious_scanners"
      description = "Block known vulnerability scanners and automated exploit probes"
      expression  = "(lower(http.user_agent) contains \"sqlmap\" or lower(http.user_agent) contains \"nikto\" or lower(http.user_agent) contains \"masscan\" or lower(http.user_agent) contains \"acunetix\" or lower(http.user_agent) contains \"censys\")"
      action      = "block"
    }
  ]
}

