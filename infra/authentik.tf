# Authentik runtime config — kleinbem.dev visitor login, Phase 2 of the
# kleinbem-auth -> Authentik migration (Phase 1: nix-config enables the
# container itself; see hosts/core-pi/default.nix).
#
# Authentik's own objects (Providers, Applications, Flows, Sources) live in
# ITS OWN database, not in NixOS config — this is genuinely Terraform's job,
# same reasoning as every other *.tf file in this directory.
#
# confidential client (has a client_secret): kleinbem-site turned out to
# already run Cloudflare Pages Functions server-side (functions/api/*.ts,
# used for the contact form's Resend/Turnstile secrets) — discovered while
# building Phase 3, contradicting this file's original "browser-only SPA,
# no backend" assumption (hence "public" client_type on first apply). With
# a real backend available, the token exchange happens server-side with
# the client_secret (PKCE stays on too, defense in depth) instead of
# purely client-side — see kleinbem-site's functions/auth/callback.ts.
#
# redirect_uris point at the callback route Phase 3 actually implements.
#
# property_mappings: the first apply omitted these, so the issued ID token
# carried only `sub` (confirmed live via the OIDC discovery doc —
# scopes_supported was just ["openid"], claims_supported had no
# name/email). Attaching openid+email+profile so the token actually
# carries something kleinbem-site's session can show. Deliberately no
# offline_access/refresh token — kleinbem-site mints its own longer-lived
# session cookie after the initial OIDC exchange rather than relying on
# Authentik token refresh, so there's no need to request it.

provider "authentik" {
  url   = "https://auth.kleinbem.dev"
  token = var.authentik_api_token
}

data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "openid" {
  scope_name = "openid"
}

data "authentik_property_mapping_provider_scope" "email" {
  scope_name = "email"
}

data "authentik_property_mapping_provider_scope" "profile" {
  scope_name = "profile"
}

resource "authentik_provider_oauth2" "kleinbem_site" {
  name        = "kleinbem-site"
  client_id   = "kleinbem-site"
  client_type = "confidential"
  # Explicit, not left to the provider's computed default: switching
  # client_type from public to confidential (above) silently reset this
  # to [] server-side — confirmed live 2026-09-21 via the API (GET
  # /api/v3/providers/oauth2/1/), which is why every authorize request
  # started failing with Authentik's generic "invalid_request / the
  # request is otherwise malformed" regardless of what else was in it.
  # grant_types is `Optional + Computed` in the provider schema, so
  # `tofu plan` never flagged this as a pending change — leaving it
  # unset let Authentik's own reset silently stick.
  grant_types = ["authorization_code"]

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://kleinbem.dev/auth/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://www.kleinbem.dev/auth/callback"
    },
  ]
}

resource "authentik_application" "kleinbem_site" {
  name              = "kleinbem.dev"
  slug              = "kleinbem-site"
  protocol_provider = authentik_provider_oauth2.kleinbem_site.id
  meta_description  = "kleinbem.dev visitor login"
}

output "kleinbem_site_oidc_client_id" {
  value = authentik_provider_oauth2.kleinbem_site.client_id
}

output "kleinbem_site_oidc_client_secret" {
  value     = authentik_provider_oauth2.kleinbem_site.client_secret
  sensitive = true
}
