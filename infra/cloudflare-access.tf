# ---------------------------------------------------------------------------
# Cloudflare Access (Zero Trust) — edge SSO in front of the browser-facing
# self-hosted apps. Free tier (≤ 50 users). Identity = email one-time-PIN, so
# no external IdP setup is needed.
#
# Scope decisions (see also cloudflare-tunnel.nix for the ingress):
#   * code.kleinbem.dev  — Code Server (no prior auth)  -> gated
#   * home.kleinbem.dev  — Dashboard (has Authelia)      -> gated (edge layer;
#                          retire Authelia later in nix-config if you want)
#   * cache.kleinbem.dev — Attic Nix cache  -> NOT gated (SSO breaks Nix pulls)
#   * n8n / chat         — use mTLS (webhooks/API)  -> NOT gated (SSO breaks them)
#
# Requires: the cloudflare_api_token to have "Access: Apps and Policies: Edit",
# and the account's Zero Trust org to exist (it does — you run a tunnel).
# ---------------------------------------------------------------------------

locals {
  access_apps = {
    "code" = {
      name   = "Code Server"
      domain = "code.kleinbem.dev"
    }
    "home" = {
      name   = "Homelab Dashboard"
      domain = "home.kleinbem.dev"
    }
  }

  # Who may pass Access. Email one-time-PIN is delivered to these addresses.
  access_allowed_emails = ["martin.kleinberger@gmail.com"]
}

resource "cloudflare_zero_trust_access_application" "this" {
  for_each = local.access_apps

  account_id                = var.cloudflare_account_id
  name                      = each.value.name
  domain                    = each.value.domain
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
}

resource "cloudflare_zero_trust_access_policy" "allow_owner" {
  for_each = local.access_apps

  application_id = cloudflare_zero_trust_access_application.this[each.key].id
  account_id     = var.cloudflare_account_id
  name           = "Allow owner (email OTP)"
  precedence     = 1
  decision       = "allow"

  include {
    email = local.access_allowed_emails
  }
}
