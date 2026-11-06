# Cloudflare Access: edge SSO (email one-time PIN or Authentik) for the
# tunnel-exposed apps in access_apps. Other public apps stay ungated because SSO
# would break their clients (n8n/chat use mTLS for webhooks and APIs); mesh-only
# apps use Authentik forward-auth instead. The API token needs
# "Access: Apps and Policies: Edit".

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

  account_id       = var.cloudflare_account_id
  name             = each.value.name
  domain           = each.value.domain
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      name       = "Allow owner (email OTP or Authentik)"
      decision   = "allow"
      precedence = 1
      include    = [for v in local.access_allowed_emails : { email = { email = v } }]
    }
  ]
}

# Authentik OIDC IdP (UUID 6bb0c00a-ad4e-4250-b5bb-215e7129112a) is set up by
# hand in Zero Trust: API tokens get 1010 (auth.forbidden) managing IdPs on this
# plan. Its ID token carries the email that allow_owner matches.

