# ---------------------------------------------------------------------------
# Cloudflare Access (Zero Trust) — edge SSO in front of the browser-facing
# self-hosted apps. Free tier (≤ 50 users). Identity = email one-time-PIN, so
# no external IdP setup is needed.
#
# Scope decisions (see also cloudflare-tunnel.nix for the ingress):
#   * home.kleinbem.dev  — Dashboard  -> gated (stays on the public tunnel;
#                          Access is its auth)
#   * vault.kleinbem.dev/admin — Vaultwarden admin panel  -> gated (PATH-scoped:
#                          only `/admin`, not the app root). The Bitwarden apps,
#                          CLI and browser extensions only ever hit /api,
#                          /identity, /notifications, /icons — all outside the
#                          Access scope — so they keep working unauthenticated
#                          at the edge (Vaultwarden's own master password + 2FA
#                          is their gate). /admin is the historically worst
#                          surface, so it gets edge SSO on top of ADMIN_TOKEN.
#   * cache.kleinbem.dev — Attic Nix cache  -> NOT gated (SSO breaks Nix pulls)
#   * n8n / chat         — use mTLS (webhooks/API)  -> NOT gated (SSO breaks them)
#   * code.kleinbem.dev  — moved to mesh-only (nix-config#mesh-only-web-services);
#                          off the tunnel, so Access can't gate it — Authentik
#                          forward-auth (auth = true on the inventory node,
#                          was Authelia until 2026-09-22) is its auth now.
#   * frigate.kleinbem.dev — mesh-only, Authentik forward-auth. Never on the tunnel.
#
# Requires: the cloudflare_api_token to have "Access: Apps and Policies: Edit",
# and the account's Zero Trust org to exist (it does — you run a tunnel).
# ---------------------------------------------------------------------------

locals {
  # `code` removed — it moved to mesh-only; Access only ever sees the tunnel's
  # 404 for it now. `home` stays: it's still on the public tunnel and Access is
  # its gate.
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
# Authentik OIDC Identity Provider for Cloudflare Access (Edge SSO)
# Replaces email one-time PIN with direct WebAuthn / YubiKey passkey auth,
# while keeping email OTP as a fallback via the policy include block.
# ---------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  account_id = var.cloudflare_account_id
  name       = "Authentik (Passkey / WebAuthn)"
  type       = "oidc"

  config {
    client_id     = authentik_provider_oauth2.oidc["cloudflare-access"].client_id
    client_secret = authentik_provider_oauth2.oidc["cloudflare-access"].client_secret
    auth_url      = "https://auth.kleinbem.dev/application/o/authorize/"
    token_url     = "https://auth.kleinbem.dev/application/o/token/"
    certs_url     = "https://auth.kleinbem.dev/application/o/cloudflare-access/jwks/"
    pkce_enabled  = true
    scopes        = ["openid", "email", "profile"]
  }
}

import {
  to = cloudflare_zero_trust_access_identity_provider.authentik
  id = "${var.cloudflare_account_id}/6bb0c00a-ad4e-4250-b5bb-215e7129112a"
}

