# Authentik runtime config — kleinbem.dev visitor login, Phase 2 of the
# kleinbem-auth -> Authentik migration (Phase 1: nix-config enables the
# container itself; see hosts/core-pi/default.nix).
#
# Authentik's own objects (Providers, Applications, Flows, Sources) live in
# ITS OWN database, not in NixOS config — this is genuinely Terraform's job,
# same reasoning as every other *.tf file in this directory.
#
# public client (no client_secret): kleinbem-site is a browser-only SPA
# (Astro+Svelte, no server backend for auth — see kleinbem-site's own
# auth-client.ts), so it authenticates via OIDC/PKCE, not a confidential
# client secret.
#
# redirect_uris below are provisional — Phase 3 (rewriting kleinbem-site's
# auth-client.ts + components against this OIDC provider) may need these
# adjusted to match whatever callback route the actual OIDC client library
# ends up using.

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

resource "authentik_provider_oauth2" "kleinbem_site" {
  name        = "kleinbem-site"
  client_id   = "kleinbem-site"
  client_type = "public"

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id

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
