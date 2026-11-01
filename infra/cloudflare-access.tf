# ---------------------------------------------------------------------------
# Cloudflare Access (Zero Trust) — edge SSO in front of the browser-facing
# self-hosted apps. Free tier (≤ 50 users). Login by email one-time PIN or
# the Authentik IdP below.
#
# Scope (ingress: nix-config modules/nixos/services/cloudflare-tunnel.nix):
#   * home.kleinbem.dev  — Dashboard  -> gated (stays on the public tunnel;
#                          Access is its auth)
#   * vault.kleinbem.dev/admin — gated, path-scoped. Bitwarden clients only use
#                          /api, /identity, /notifications, /icons, so they
#                          stay ungated; /admin gets SSO on top of ADMIN_TOKEN.
#   * cache.kleinbem.dev — Attic Nix cache  -> NOT gated (SSO breaks Nix pulls)
#   * n8n / chat         — use mTLS (webhooks/API)  -> NOT gated (SSO breaks them)
#   * code, frigate      — mesh-only, not on the tunnel; Authentik forward-auth.
#
# Requires: the cloudflare_api_token to have "Access: Apps and Policies: Edit",
# and the account's Zero Trust org to exist (it does — you run a tunnel).
# ---------------------------------------------------------------------------

locals {
  access_apps = {
    "home" = {
      name   = "Homelab Dashboard"
      domain = "home.kleinbem.dev"
    }
    # Path-scoped: this app matches ONLY vault.kleinbem.dev/admin. Everything
    # else under vault.kleinbem.dev stays un-gated so Bitwarden clients work.
    "vault-admin" = {
      name   = "Vaultwarden Admin"
      domain = "vault.kleinbem.dev/admin"
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
  name           = "Allow owner (email OTP or Authentik)"
  precedence     = 1
  decision       = "allow"

  include {
    email = local.access_allowed_emails
  }
}

# ---------------------------------------------------------------------------
# Authentik OIDC Identity Provider for Cloudflare Access
# Live IdP UUID: 6bb0c00a-ad4e-4250-b5bb-215e7129112a
#
# Set up by hand in Zero Trust (Integrations > Identity providers): API tokens
# get 1010 (auth.forbidden) managing IdPs on this plan. Authentik's ID token
# carries the email that allow_owner matches.
# ---------------------------------------------------------------------------

