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

# Brand-level flows — distinct slugs from the two provider-level ones above
# (no "provider" in the name), used by authentik_brand.kleinbem_site below.
data "authentik_flow" "default_authentication_flow" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default_invalidation_flow_brand" {
  slug = "default-invalidation-flow"
}

data "authentik_flow" "default_user_settings_flow" {
  slug = "default-user-settings-flow"
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
  # Shows the "Sign in with Google" button on the login page — same
  # `.uuid`-not-`.id` gotcha as authentik_flow above (source_oauth also
  # has a `slug` field, so its `id` is the slug too, not the real UUID
  # foreign-key references need).
  sources = [authentik_source_oauth.google.uuid]
}

import {
  to = authentik_stage_identification.default_authentication_identification
  id = "382698eb-4661-46b5-9c29-a9437788e70e"
}

# --- Google sign-in ("cannot see that" — user noticed it was missing,
# confirmed 2026-09-21 it worked on kleinbem-auth before) ---
#
# Reuses kleinbem-auth's own Google OAuth 2.0 Web Client (still a real,
# populated credential on core-pi, confirmed live — not a new one, since
# no fresh Google Cloud Console access was needed for this). That client's
# "Authorized redirect URIs" list in Google Cloud Console needs a SECOND
# entry added by hand (can't be done via this Terraform — Google Cloud
# Console, not something with an API token available here): Authentik's
# own callback path, output below as google_source_callback_uri once
# applied. The existing entry (kleinbem-auth's
# https://login.kleinbem.dev/api/auth/callback/google) stays — it's
# additive, not a replacement, so kleinbem-auth's own Google login keeps
# working until Phase 4 decommissions it.
#
# authentication_flow/enrollment_flow: default-source-authentication and
# default-source-enrollment are EXACTLY what these two are for — unlike
# the identification stage's own enrollment_flow (built standalone above
# because default-source-enrollment's own if-sso policy blocks direct
# use), a Source is precisely the "arriving via SSO" context that policy
# is checking for.
#
# No property_mappings: this instance has zero source-oauth property
# mappings at all (confirmed live — GET .../propertymappings/source/
# oauth/ returns zero results), so there's nothing to attach; Authentik's
# built-in provider_type="google" handling still maps name/email itself.
data "authentik_flow" "default_source_authentication" {
  slug = "default-source-authentication"
}

data "authentik_flow" "default_source_enrollment" {
  slug = "default-source-enrollment"
}

resource "authentik_source_oauth" "google" {
  name                = "Google"
  slug                = "google"
  provider_type       = "google"
  consumer_key        = var.kleinbem_auth_google_client_id
  consumer_secret     = var.kleinbem_auth_google_client_secret
  authentication_flow = data.authentik_flow.default_source_authentication.id
  enrollment_flow     = data.authentik_flow.default_source_enrollment.id
  enabled             = true
}

output "google_source_callback_uri" {
  value       = authentik_source_oauth.google.callback_uri
  description = "Add this as a SECOND 'Authorized redirect URI' on kleinbem-auth's existing Google OAuth client in Google Cloud Console — don't remove the existing login.kleinbem.dev one."
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

# --- Branding: make auth.kleinbem.dev look like part of kleinbem.dev ---
#
# User feedback 2026-09-21: the hosted login/signup page "looks like a
# different website" (stock authentik title, mountain-photo flow
# background). Considered embedding the flow executor as native Svelte
# components on kleinbem-site itself, but authentik sends no CORS headers
# on the flow-executor API (confirmed live) — the only way to make that
# same-origin would be a session-cookie-translating reverse proxy in front
# of the IdP, which is a lot of new attack surface for what is fundamentally
# a cosmetic ask. This — a scoped Brand with custom CSS — gets the same
# visual outcome (matches kleinbem-site's palette, no more stock imagery)
# with zero new runtime code and zero risk to the login flow itself.
#
# A NEW Brand scoped to the real hostname, not an import/edit of the
# existing default (`domain = "authentik-default", default = true`) —
# authentik matches brands by exact request domain first, falling back to
# the default one, so this one taking effect for auth.kleinbem.dev needs no
# import block and can't affect any other domain/tenant on this instance.
#
# First pass used authentik's documented semantic --ak-color-* variables
# (website/docs/customize/branding/custom-css.mdx) — applied cleanly
# (confirmed live: the brand's custom CSS IS adopted into every managed
# shadow root, e.g. ak-flow-executor, ak-message-container, ak-flow-card —
# checked via el.shadowRoot.adoptedStyleSheets from the browser console),
# but had ZERO visual effect. Root cause, found by inspecting the actual
# rendered DOM live: this version's login page (v2026.8.0) renders classic
# PatternFly 4 markup (.pf-c-login, .pf-c-button.pf-m-primary, …), which
# doesn't consume the --ak-color-* bridge at all — that variable set
# appears to be for authentik's newer/other UI surfaces, not this one. A
# second bug compounded it: the CSS used `:root { ... }` selectors, which
# adopted-into-a-shadow-root stylesheets can never match (no element
# inside a shadow tree is ever the document root) — so even a variable
# this page DOES read would never have been set. Confirmed by testing
# direct PatternFly class overrides live (script-injected adoptedStyleSheets
# via the browser console before writing this) — that's what actually
# moves pixels, hence the plain selectors below instead of the CSS-variable
# approach the docs recommend as the primary path.
#
# --ak-global--background-image is the one variable that DOES work here —
# unrelated to the shadow-root adoption above, it's set by a plain
# (non-shadow) <style> tag in authentik's own flow.html
# (authentik/flows/templates/if/flow.html), so a :root override at the
# top-level document genuinely reaches it.
#
# Known minor gap: the "Continue with Google" button's "G" icon is
# authentik's static asset (/static/authentik/sources/google.svg, an
# actual image, not an inline SVG using fill:currentColor) — white-on-
# transparent by design for a dark button. Gave the button an accent-blue
# pill background so it stays visible against the new light page; a
# perfect-contrast fix would need a different icon asset, not reachable
# via this provider — not worth chasing further for one small icon.
#
# Values pulled straight from kleinbem-site/src/styles/global.css's
# --color-* tokens, so a future palette change there should be mirrored
# here too.
resource "authentik_brand" "kleinbem_site" {
  domain         = "auth.kleinbem.dev"
  default        = false
  branding_title = "kleinbem.dev"

  # Real bug, found live 2026-09-22: authentik matches Brands by exact
  # request domain, so once this Brand existed, EVERY request to
  # auth.kleinbem.dev started resolving its flow_* fields from here instead
  # of falling back to authentik-default's (which has real flows
  # configured) — and this Brand only ever set branding_*/attributes,
  # leaving flow_authentication/flow_invalidation/flow_user_settings all
  # null. Login itself kept working (the flow executor resolves slugs
  # straight from the URL, not the Brand), but the "My Applications"
  # launcher (/if/user/) needs flow_user_settings specifically and
  # 403'd — reproduced live, confirmed via GET .../core/brands/: this
  # Brand's flow_user_settings was None while authentik-default's wasn't.
  # Mirroring authentik-default's own values exactly, not inventing new
  # flows — this Brand exists for branding, not to diverge behavior.
  flow_authentication = data.authentik_flow.default_authentication_flow.id
  flow_invalidation   = data.authentik_flow.default_invalidation_flow_brand.id
  flow_user_settings  = data.authentik_flow.default_user_settings_flow.id
  # kleinbem-site's own mark (public/favicon.svg — a plain 32x32 "K"
  # monogram, already served at kleinbem.dev/favicon.svg) instead of the
  # stock authentik wordmark. branding_favicon reuses the same asset — no
  # separate favicon exists for this narrower purpose, and reusing it here
  # means one source of truth if the mark ever changes.
  branding_logo    = "https://kleinbem.dev/favicon.svg"
  branding_favicon = "https://kleinbem.dev/favicon.svg"

  # Forces the actual theme, rather than fighting authentik's automatic
  # (system-preference-driven) dark mode purely with CSS !important —
  # matches kleinbem-site's own explicit design (src/styles/global.css:
  # "This is a LIGHT site by design — no dark scheme"). Confirmed live
  # 2026-09-22 that a visitor's dark OS preference otherwise DOES flip
  # authentik into its real dark theme (populated --ak-dark-background
  # etc., not a placeholder), so this isn't defensive — without it the
  # page would only look right for light-preference visitors even with
  # the CSS below in place. Documented mechanism: goauthentik/authentik
  # website/docs/customize/branding/custom-css.mdx, "Enforce a specific
  # color scheme".
  attributes = jsonencode({
    settings = {
      theme = {
        base = "light"
      }
    }
  })

  branding_custom_css = <<-CSS
    :root,
    html[data-theme="dark"] {
      --ak-global--background-image: none !important;
    }

    .pf-c-login,
    .pf-c-login__main {
      background-color: #f9f9ff !important;
    }

    .pf-c-login__main-header,
    .pf-c-login__main-body,
    .pf-c-title,
    .pf-c-login__main-footer-band {
      color: #1a1b20 !important;
    }

    a {
      color: #435e91 !important;
    }

    .pf-c-button.pf-m-primary {
      background-color: #435e91 !important;
    }

    .pf-c-login__footer,
    .pf-c-login__footer a,
    ak-locale-select,
    ak-locale-select label,
    ak-locale-select select {
      color: #44474f !important;
    }

    .source-button {
      background-color: #435e91 !important;
      border-radius: 999px !important;
    }
  CSS
}

# --- Fleet forward-auth (Authelia migration, step 1 of the plan) ---
#
# Authelia currently gates 6 services on core-pi via a shared Caddy
# forward_auth block (nix-presets/containers/caddy/helpers.nix), keyed off
# one `auth = true` flag per inventory.nix node. Consolidating onto
# Authentik instead of running two identity systems — see kleinbem_site's
# own header comment for the same reasoning.
#
# authentik's EMBEDDED outpost (already running as part of the existing
# `authentik` container on core-pi, port 9000 — no separate
# outpost deployment) handles Proxy-Provider forward-auth natively at
# /outpost.goauthentik.io/auth/caddy. `mode = "forward_domain"` +
# cookie_domain covers every *.kleinbem.dev subdomain with ONE
# Provider+Application and a shared session cookie — confirmed via the
# provider's own resource docs, not one Provider per protected service.
#
# Scope: code-server, monitoring's alertmanager, syncthing, frigate,
# paperless, and n8n's UI (n8n's own /webhook*/webhook-test* paths are
# carved out at the Caddy layer instead — see
# nix-presets/containers/caddy/helpers.nix's authExcludePaths and
# inventory.nix's n8n node — external webhook callers can't complete an
# interactive Authentik login). NOT Grafana — it gets native OIDC below
# instead of forward-auth, since it has first-class support for that and
# shouldn't sit behind a second auth layer on top of its own login.
#
# One Provider+Application PER service (forward_single), not one shared
# forward_domain Provider — a deliberate switch 2026-09-22 after the
# shared version shipped: martin wanted distinct tiles in /if/user/ ("My
# Applications") instead of one generic "Fleet internal services" tile
# covering all 6 with no way to tell them apart or launch a specific one.
# Side benefit, not the original motivation: independent per-service
# cookies and policy bindings instead of one shared cookie_domain session
# — a compromised cookie for one service no longer implies the others,
# and different services could get different access policies later if
# ever needed (all bound to the same "staff" group for now, unchanged).
# Caddy's config needs ZERO changes for this — every `auth = true` node
# already calls the same generic outpost endpoint
# (10.85.48.142:9000/outpost.goauthentik.io/auth/caddy); the outpost
# itself routes by Host header to whichever of these Providers matches,
# same as it already did with one Provider matching a wider domain set.
locals {
  fleet_services = {
    code-server = {
      name   = "code-server"
      domain = "code.kleinbem.dev"
      desc   = "Browser-based VS Code IDE"
    }
    syncthing = {
      name   = "Syncthing"
      domain = "syncthing.kleinbem.dev"
      desc   = "File sync"
    }
    alertmanager = {
      name   = "Alertmanager"
      domain = "alertmanager.kleinbem.dev"
      desc   = "Prometheus alert routing"
    }
    frigate = {
      name   = "Frigate"
      domain = "frigate.kleinbem.dev"
      desc   = "Camera NVR"
    }
    paperless = {
      name   = "Paperless"
      domain = "paperless.kleinbem.dev"
      desc   = "Document management"
    }
    n8n = {
      name   = "n8n"
      domain = "n8n.kleinbem.dev"
      desc   = "Workflow automation (UI only — /webhook* stays unauthenticated at the Caddy layer, see caddy/helpers.nix)"
    }
  }
}

resource "authentik_provider_proxy" "fleet" {
  for_each      = local.fleet_services
  name          = "fleet-${each.key}"
  mode          = "forward_single"
  external_host = "https://${each.value.domain}"

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
}

resource "authentik_application" "fleet" {
  for_each          = local.fleet_services
  name              = each.value.name
  slug              = "fleet-${each.key}"
  protocol_provider = authentik_provider_proxy.fleet[each.key].id
  meta_description  = each.value.desc
  # Each tile now launches its own real service directly — the previous
  # shared Application had no single sensible target (it covered 6
  # different domains) and pointed at the fleet dashboard instead.
  meta_launch_url = "https://${each.value.domain}"
}

# Creating a Provider does NOT attach it to anything — outposts have their
# OWN explicit provider list, and this instance's embedded outpost had zero
# providers before this (confirmed live via GET /api/v3/outposts/instances/
# 2026-09-22: "providers": []). Without this, Caddy's calls to
# /outpost.goauthentik.io/auth/caddy 404 unconditionally — the outpost has
# no idea what it's supposed to be protecting. Adopts the existing
# "authentik Embedded Outpost" (real UUID, not the container.nix-scoped
# one — checked live) rather than creating a competing outpost, same
# import-block pattern as default_authentication_identification above.
resource "authentik_outpost" "embedded" {
  name               = "authentik Embedded Outpost"
  protocol_providers = [for p in authentik_provider_proxy.fleet : p.id]

  # Real bug, found live 2026-09-22: authentik_host/authentik_host_browser
  # were both "" (confirmed via GET .../outposts/instances/<uuid>/), so the
  # outpost fell back to constructing http://localhost/... for the
  # internal authorize-continuation redirect during forward-auth — a real
  # browser hitting that gets ERR_CONNECTION_REFUSED trying to reach its
  # own machine. Invisible for 5 of the 6 fleet services (mesh-only,
  # 404 at the Cloudflare edge before ever reaching the outpost) but broke
  # n8n's completion (public tunnel, so it got far enough to hit this).
  # Every other key below is `config`'s own existing default — listed
  # explicitly because this field is Generated/Computed, same reasoning as
  # every other adopted-object field in this file: an omitted key here
  # means "reset to schema default", not "leave whatever's live alone".
  config = jsonencode({
    log_level                        = "info"
    docker_labels                    = null
    authentik_host                   = "https://auth.kleinbem.dev"
    docker_network                   = null
    container_image                  = null
    docker_map_ports                 = true
    refresh_interval                 = "minutes=5"
    kubernetes_replicas              = 1
    kubernetes_namespace             = "default"
    authentik_host_browser           = "https://auth.kleinbem.dev"
    object_naming_template           = "ak-outpost-%(name)s"
    authentik_host_insecure          = false
    kubernetes_json_patches          = null
    kubernetes_service_type          = "ClusterIP"
    kubernetes_ingress_path_type     = null
    kubernetes_image_pull_secrets    = []
    kubernetes_ingress_class_name    = null
    kubernetes_disable_x509_strict   = false
    kubernetes_disabled_components   = []
    kubernetes_ingress_annotations   = {}
    kubernetes_ingress_secret_name   = "authentik-outpost-tls"
    kubernetes_httproute_annotations = {}
    kubernetes_httproute_parent_refs = []
  })
}

import {
  to = authentik_outpost.embedded
  id = "1bf3fce7-cdc2-49ac-983b-beab8401f24e"
}

# --- Grafana: native OIDC, not forward-auth ---
#
# Same authentik_provider_oauth2 pattern as kleinbem_site above (not
# authentik_provider_proxy) — Grafana authenticates visitors itself via
# services.grafana.settings.auth.generic_oauth rather than sitting behind
# the shared forward-auth gate. grant_types set explicitly even though
# this is a fresh resource (not a public->confidential switch like
# kleinbem_site hit) — same defensive reasoning: it's Optional+Computed in
# the provider schema, cheap to pin, expensive to silently lose.
resource "authentik_provider_oauth2" "grafana" {
  name        = "grafana"
  client_id   = "grafana"
  client_type = "confidential"
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
      url           = "https://grafana.kleinbem.dev/login/generic_oauth"
    }
  ]
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_description  = "kleinbem fleet monitoring dashboard"
}

output "grafana_oidc_client_id" {
  value = authentik_provider_oauth2.grafana.client_id
}

output "grafana_oidc_client_secret" {
  value     = authentik_provider_oauth2.grafana.client_secret
  sensitive = true
}

# --- Access scoping: internal infra is NOT for kleinbem.dev visitors ---
#
# Both Applications above and kleinbem_site's own Application live on the
# SAME authentik instance/user directory as kleinbem.dev's public
# self-registration flow — without an explicit access policy, anyone who
# signs up on kleinbem.dev could also authenticate into Grafana, Paperless,
# code-server, etc. Scoping internal infra to a "staff" group (currently:
# just martin, the existing user — decided explicitly, not everyone the
# directory happens to contain) is what actually enforces that boundary;
# the two authentik_application resources above have no access
# restriction of their own.
#
# Adopted (import block below) rather than left as a data source — a real
# bug needed a real field changed. Google-source sign-in creates accounts
# as type="external" by default (confirmed live via GET
# /api/v3/core/users/7/), and authentik restricts /if/user/ ("My
# Applications") to type="internal" only: "Request has been denied.
# Interface can only be accessed by internal users." — reproduced live
# 2026-09-22, martin's own account, in both a normal and an incognito
# session (ruling out cookies/cache). Every other field below matches the
# live account exactly — same discipline as the identification-stage
# adoption above, so this apply only changes `type`, nothing else.
resource "authentik_user" "martin" {
  username  = "martin.kleinberger@gmail.com"
  name      = "Martin Kleinberger"
  email     = "martin.kleinberger@gmail.com"
  is_active = true
  path      = "goauthentik.io/sources/google"
  type      = "internal"
  # Group membership stays owned by authentik_group.staff's `users` field
  # below, not mirrored here too — both sides are the same underlying M2M
  # relationship (each schema doc marks its own field "Generated"), and
  # setting it on both would make these two resources depend on each
  # other circularly.
  attributes = jsonencode({
    "goauthentik.io/user/sources" = ["Google"]
  })
}

import {
  to = authentik_user.martin
  id = "7"
}

resource "authentik_group" "staff" {
  name  = "staff"
  users = [authentik_user.martin.id]
}

resource "authentik_policy_binding" "fleet_staff_only" {
  for_each = authentik_application.fleet
  target   = each.value.uuid
  group    = authentik_group.staff.id
  order    = 0
}

resource "authentik_policy_binding" "grafana_staff_only" {
  target = authentik_application.grafana.uuid
  group  = authentik_group.staff.id
  order  = 0
}
