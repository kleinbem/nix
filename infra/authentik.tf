# Authentik runtime config: the container is NixOS (nix-config hosts/core-pi),
# but Providers, Applications, Flows and Sources live in Authentik's database.
# kleinbem-site is a confidential client (server-side code exchange plus PKCE).
# Without the openid/email/profile mappings the ID token carries only `sub`.

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

locals {
  # Authentik's system keypair. With a signing key set, providers use RS256
  # and publish keys at /jwks/, which Cloudflare Access requires.
  authentik_jwt_cert_id = "5d46e643-75cf-45a9-b623-46f8dd95e5ee"
}

# --- Self-registration for kleinbem.dev visitors ---
# Not default-source-enrollment: its if-sso policy denies it outside a Source
# login. Own stages so SSO flow changes can't leak in. No email verification
# because no SMTP transport is configured.
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

# password/password_repeat keys match default-password-change: that pair is
# what the prompt stage checks as "must match".
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

# Same thresholds as default-password-change-password-policy.
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

# Adopts the built-in identification stage (the login screen) via import.
# No field here is computed, so an omitted one resets to empty on apply:
# list every live value, not just the ones we change.
resource "authentik_stage_identification" "default_authentication_identification" {
  name                      = "default-authentication-identification"
  user_fields               = ["email", "username"]
  case_insensitive_matching = true
  show_matched_user         = true
  pretend_user_exists       = true
  # No recovery flow ("forgot password"): it needs outbound email.
  enrollment_flow = authentik_flow.kleinbem_site_enrollment.uuid
  # `.uuid`, not `.id`: for slugged objects `id` is the slug.
  sources = [authentik_source_oauth.google.uuid]
}

import {
  to = authentik_stage_identification.default_authentication_identification
  id = "382698eb-4661-46b5-9c29-a9437788e70e"
}

# --- Google sign-in ---
# Uses the kleinbem-auth Google OAuth client; its redirect URIs are set by hand
# in Google Cloud Console (add google_source_callback_uri there). A Source is
# the SSO context the default-source-* flows expect.
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

  # Authentik fills these from the Google type and stores them; left unset,
  # every plan wants to null them.
  authorization_url = "https://accounts.google.com/o/oauth2/v2/auth"
  access_token_url  = "https://oauth2.googleapis.com/token"
  profile_url       = "https://openidconnect.googleapis.com/v1/userinfo"
  oidc_jwks_url     = "https://www.googleapis.com/oauth2/v3/certs"
}

output "google_source_callback_uri" {
  value       = authentik_source_oauth.google.callback_uri
  description = "Add this as a SECOND 'Authorized redirect URI' on kleinbem-auth's existing Google OAuth client in Google Cloud Console — don't remove the existing login.kleinbem.dev one."
}

resource "authentik_provider_oauth2" "kleinbem_site" {
  name        = "kleinbem-site"
  client_id   = "kleinbem-site"
  client_type = "confidential"
  # Pinned: grant_types is Optional+Computed, so a server-side reset to []
  # never shows in the plan, and every authorize request then fails with
  # "invalid_request".
  grant_types = ["authorization_code"]

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  signing_key        = local.authentik_jwt_cert_id

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  # redirect_uri_type is the server's default, but Authentik stores it on
  # this provider and the plan showed it as a diff on every apply; declaring
  # it keeps the plan clean.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://kleinbem.dev/auth/callback"
    },
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://www.kleinbem.dev/auth/callback"
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
# Brands match by exact domain, so the default brand is untouched. The login
# page's PatternFly 4 markup ignores --ak-color-* and `:root` doesn't match in
# the shadow roots, so the CSS overrides .pf-c-* directly (except the
# background image, set in flow.html's top-level <style>).
# Colors mirror kleinbem-site/src/styles/global.css; keep them in sync.
resource "authentik_brand" "kleinbem_site" {
  domain         = "auth.kleinbem.dev"
  default        = false
  branding_title = "kleinbem.dev"

  # This Brand replaces the default's flow_* fields for this domain too, so
  # copy the default's values. Without flow_user_settings, /if/user/ 403s.
  flow_authentication = data.authentik_flow.default_authentication_flow.id
  flow_invalidation   = data.authentik_flow.default_invalidation_flow_brand.id
  flow_user_settings  = data.authentik_flow.default_user_settings_flow.id
  # kleinbem-site's "K" mark (public/favicon.svg) as logo and favicon.
  branding_logo    = "https://kleinbem.dev/favicon.svg"
  branding_favicon = "https://kleinbem.dev/favicon.svg"

  # Force light: kleinbem-site has no dark scheme, and a dark OS preference
  # otherwise switches Authentik to its dark theme under the CSS below.
  attributes = jsonencode({
    settings = {
      theme = {
        base = "light"
      }
    }
  })

  # Authentik trims the trailing newline on save, so chomp it here too.
  branding_custom_css = chomp(<<-CSS
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
  )
}

# --- Fleet forward-auth ---
# Caddy's forward_auth (nix-presets containers/caddy/helpers.nix) sends every
# `auth = true` inventory node to the embedded outpost, which picks the
# Provider by Host header. One forward_single Provider per service gives each
# its own tile, cookie and policy binding. Native OIDC apps go in oidc_apps.
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
  meta_launch_url   = "https://${each.value.domain}"
}

# Providers only serve once listed on an outpost; otherwise Caddy's
# /outpost.goauthentik.io/auth/caddy calls 404. Adopts the existing
# embedded outpost via import rather than creating a second one.
resource "authentik_outpost" "embedded" {
  name               = "authentik Embedded Outpost"
  protocol_providers = [for p in authentik_provider_proxy.fleet : p.id]

  # authentik_host*: left empty, the outpost redirects browsers to
  # http://localhost/ after login. The other keys are the defaults, listed
  # because an omitted key resets on apply.
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

# --- Native OIDC services ---
# Kept out of Caddy's forward-auth so API clients (extensions, agents, mobile
# apps) keep direct token access. grant_types is pinned as on kleinbem_site.
locals {
  oidc_apps = {
    grafana = {
      name          = "Grafana"
      redirect_uris = ["https://grafana.kleinbem.dev/login/generic_oauth"]
      desc          = "Fleet monitoring dashboard"
      launch_url    = "https://grafana.kleinbem.dev"
    }
    # Garage UI on nixos-nvme (nix-presets containers/garage-ui.nix). Members
    # of `staff` (the groups claim) are admins there; the binding below keeps
    # everyone else out anyway.
    garage-ui = {
      name          = "Garage UI"
      redirect_uris = ["https://garage.kleinbem.dev/auth/oidc/callback"]
      desc          = "Garage S3 buckets, keys and layout"
      launch_url    = "https://garage.kleinbem.dev"
    }
    open-webui = {
      name          = "Open WebUI"
      redirect_uris = ["https://chat.kleinbem.dev/oauth/oidc/callback"]
      desc          = "Fleet AI chat interface"
      launch_url    = "https://chat.kleinbem.dev"
    }
    # Forgejo on mac-mini (nix-presets containers/forgejo.nix). The preset
    # names its login source "authentik", which sets the callback path.
    forgejo = {
      name          = "Forgejo"
      redirect_uris = ["https://git.kleinbem.dev/user/oauth2/authentik/callback"]
      desc          = "Self-hosted Git forge"
      launch_url    = "https://git.kleinbem.dev"
    }
    # HA's auth_oidc component logs in with PKCE as a public client, so no
    # secret ships into the container. The second redirect URI is the LAN
    # address (hass-pi's nftables DNAT), for when Caddy/DNS are down.
    home-assistant = {
      name        = "Home Assistant"
      client_type = "public"
      redirect_uris = [
        "https://hass.kleinbem.dev/auth/oidc/callback",
        "http://10.0.0.21:8123/auth/oidc/callback",
      ]
      desc       = "Smart home (hass-pi)"
      launch_url = "https://hass.kleinbem.dev"
    }
    cloudflare-access = {
      name = "Cloudflare Access"
      redirect_uris = [
        "https://sparkling-feather-0ab4.cloudflareaccess.com/cdn-cgi/access/callback",
        "^https://.*\\.cloudflareaccess\\.com/cdn-cgi/access/callback$",
      ]
      matching_mode = "regex"
      desc          = "Cloudflare Zero Trust edge SSO (Passkey / WebAuthn)"
      launch_url    = "https://home.kleinbem.dev"
    }
  }
}

resource "authentik_provider_oauth2" "oidc" {
  for_each    = local.oidc_apps
  name        = each.key
  client_id   = each.key
  client_type = try(each.value.client_type, "confidential")
  grant_types = ["authorization_code"]

  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  signing_key        = local.authentik_jwt_cert_id

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  # Declared for the same reason as on kleinbem-site: Authentik stores the
  # default and the plan otherwise shows it as a diff on every apply.
  allowed_redirect_uris = [
    for uri in each.value.redirect_uris : {
      matching_mode     = try(each.value.matching_mode, "strict")
      redirect_uri_type = "authorization"
      url               = uri
    }
  ]
}

resource "authentik_application" "oidc" {
  for_each          = local.oidc_apps
  name              = each.value.name
  slug              = each.key
  protocol_provider = authentik_provider_oauth2.oidc[each.key].id
  meta_description  = each.value.desc
  meta_launch_url   = each.value.launch_url
}

# State migration: move existing Grafana resources cleanly without recreation
moved {
  from = authentik_provider_oauth2.grafana
  to   = authentik_provider_oauth2.oidc["grafana"]
}

moved {
  from = authentik_application.grafana
  to   = authentik_application.oidc["grafana"]
}

moved {
  from = authentik_policy_binding.grafana_staff_only
  to   = authentik_policy_binding.oidc_staff_only["grafana"]
}

output "oidc_client_ids" {
  value = {
    for k, p in authentik_provider_oauth2.oidc : k => p.client_id
  }
}

output "oidc_client_secrets" {
  value = {
    for k, p in authentik_provider_oauth2.oidc : k => p.client_secret
  }
  sensitive = true
}

# Legacy outputs preserved for backward compatibility
output "grafana_oidc_client_id" {
  value = authentik_provider_oauth2.oidc["grafana"].client_id
}

output "grafana_oidc_client_secret" {
  value     = authentik_provider_oauth2.oidc["grafana"].client_secret
  sensitive = true
}

output "open_webui_oidc_client_id" {
  value = authentik_provider_oauth2.oidc["open-webui"].client_id
}

output "open_webui_oidc_client_secret" {
  value     = authentik_provider_oauth2.oidc["open-webui"].client_secret
  sensitive = true
}



# --- Access scoping: internal infra is NOT for kleinbem.dev visitors ---
# Visitors self-register in the same directory, so every fleet and OIDC app
# is bound to the "staff" group. martin is imported to set type = internal:
# Google sign-in creates "external" users, who can't open /if/user/.
resource "authentik_user" "martin" {
  username  = "martin.kleinberger@gmail.com"
  name      = "Martin Kleinberger"
  email     = "martin.kleinberger@gmail.com"
  is_active = true
  path      = "goauthentik.io/sources/google"
  type      = "internal"
  # Membership is set on authentik_group.staff only; setting it on both
  # sides makes the two resources depend on each other.
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

resource "authentik_policy_binding" "oidc_staff_only" {
  for_each = authentik_application.oidc
  target   = each.value.uuid
  group    = authentik_group.staff.id
  order    = 0
}


