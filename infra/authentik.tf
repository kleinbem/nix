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

# --- Self-registration for kleinbem.dev visitors ---
#
# First attempt at this pointed enrollment_flow (below) at Authentik's
# built-in default-source-enrollment flow, on the assumption that it was
# a general-purpose "create a local account" flow. Wrong: it carries a
# policy (default-source-enrollment-if-sso, expression `return
# ak_is_sso_flow`) that only lets it run when arriving via an external
# Source (Google/GitHub sign-in creating a matching local account) — used
# directly, every attempt hits "Request has been denied" (confirmed live
# 2026-09-21). Its own prompt stage only asks for a username, since an
# SSO login already supplies email/name — not reusable for real email
# +password registration either. This instance genuinely doesn't ship a
# general-purpose enrollment flow out of the box, so one is built here
# instead of adopted.
#
# user_write/user_login stages are dedicated, Terraform-owned copies
# rather than reusing default-source-enrollment's — its user_write config
# happened to already be generic enough to share (checked live), but
# owning independent copies means a future change to the SSO flow can
# never silently affect this one, and vice versa.
#
# No email-verification stage: that needs a working EmailStage + SMTP
# transport, which isn't configured on this instance (the same gap
# already noted above for the missing recovery/forgot-password flow) — a
# self-registered address is trusted as entered for now.
resource "authentik_flow" "kleinbem_site_enrollment" {
  name        = "kleinbem-site-enrollment"
  slug        = "kleinbem-site-enrollment"
  title       = "Create your kleinbem.dev account"
  designation = "enrollment"
}

resource "authentik_stage_prompt_field" "enrollment_username" {
  name      = "kleinbem-site-enrollment-field-username"
  field_key = "username"
  label     = "Username"
  type      = "username"
  required  = true
  order     = 100
}

resource "authentik_stage_prompt_field" "enrollment_name" {
  name      = "kleinbem-site-enrollment-field-name"
  field_key = "name"
  label     = "Name"
  type      = "text"
  required  = true
  order     = 110
}

resource "authentik_stage_prompt_field" "enrollment_email" {
  name      = "kleinbem-site-enrollment-field-email"
  field_key = "email"
  label     = "Email"
  type      = "email"
  required  = true
  order     = 120
}

# field_key/type/order here match default-password-change's own password
# fields exactly (checked live) — that's the pairing Authentik's prompt
# stage actually knows how to cross-validate as "these two must match",
# not something configurable elsewhere.
resource "authentik_stage_prompt_field" "enrollment_password" {
  name      = "kleinbem-site-enrollment-field-password"
  field_key = "password"
  label     = "Password"
  type      = "password"
  required  = true
  order     = 300
}

resource "authentik_stage_prompt_field" "enrollment_password_repeat" {
  name      = "kleinbem-site-enrollment-field-password-repeat"
  field_key = "password_repeat"
  label     = "Password (repeat)"
  type      = "password"
  required  = true
  order     = 301
}

# Same thresholds as default-password-change-password-policy (checked
# live) — not stricter, not looser, just consistent with what this
# instance already enforces everywhere else a password gets set.
resource "authentik_policy_password" "enrollment_password_policy" {
  name           = "kleinbem-site-enrollment-password-policy"
  password_field = "password"
  length_min     = 8
  check_zxcvbn   = true
  error_message  = "Password needs to be 8 characters or longer."
}

resource "authentik_stage_prompt" "kleinbem_site_enrollment_prompt" {
  name = "kleinbem-site-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.enrollment_username.id,
    authentik_stage_prompt_field.enrollment_name.id,
    authentik_stage_prompt_field.enrollment_email.id,
    authentik_stage_prompt_field.enrollment_password.id,
    authentik_stage_prompt_field.enrollment_password_repeat.id,
  ]
  validation_policies = [authentik_policy_password.enrollment_password_policy.id]
}

resource "authentik_stage_user_write" "kleinbem_site_enrollment_write" {
  name                     = "kleinbem-site-enrollment-write"
  user_creation_mode       = "always_create"
  create_users_as_inactive = false
  user_type                = "external"
}

resource "authentik_stage_user_login" "kleinbem_site_enrollment_login" {
  name = "kleinbem-site-enrollment-login"
}

resource "authentik_flow_stage_binding" "enrollment_prompt" {
  target = authentik_flow.kleinbem_site_enrollment.uuid
  stage  = authentik_stage_prompt.kleinbem_site_enrollment_prompt.id
  order  = 10
}

resource "authentik_flow_stage_binding" "enrollment_write" {
  target = authentik_flow.kleinbem_site_enrollment.uuid
  stage  = authentik_stage_user_write.kleinbem_site_enrollment_write.id
  order  = 20
}

resource "authentik_flow_stage_binding" "enrollment_login" {
  target = authentik_flow.kleinbem_site_enrollment.uuid
  stage  = authentik_stage_user_login.kleinbem_site_enrollment_login.id
  order  = 30
}

# Adopts Authentik's own built-in identification stage (the "Email or
# Username" screen on the login page) rather than creating a duplicate —
# see the import block below. Every field here matches its current live
# value (checked via GET /api/v3/stages/identification/<pk>/ before
# writing this) except enrollment_flow, so adopting it doesn't reset
# anything else. None of this resource's fields are marked `computed` in
# the provider schema (unlike grant_types on the OAuth2 provider above)
# — an omitted field here really does mean "false/null/empty", not
# "leave whatever's live alone", so every non-default current value has
# to be listed explicitly or this apply would silently disable it (e.g.
# dropping `user_fields` back to empty would stop matching visitors by
# email/username at all).
resource "authentik_stage_identification" "default_authentication_identification" {
  name                      = "default-authentication-identification"
  user_fields               = ["email", "username"]
  case_insensitive_matching = true
  show_matched_user         = true
  pretend_user_exists       = true
  # "Forgot password" stays unavailable for a different reason: Authentik
  # has no recovery-designation flow at all yet (confirmed live — GET
  # .../flows/instances/?designation=recovery returns zero results),
  # because that needs working outbound email, which isn't configured.
  enrollment_flow = authentik_flow.kleinbem_site_enrollment.uuid
}

import {
  to = authentik_stage_identification.default_authentication_identification
  id = "382698eb-4661-46b5-9c29-a9437788e70e"
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
