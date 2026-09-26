# Google Cloud — one project, `kleinbem-ai`, holding: (1) per-persona Gemini
# API keys, (2) the "Sign in with Google" OAuth client, originally created
# for kleinbem-auth's login.kleinbem.dev (that service decommissioned
# 2026-09-21) and now reused by Authentik's Google Source for kleinbem.dev
# visitor login instead — see authentik.tf. The project was created
# manually via gcloud (2026-08-07,
# no org/Cloud Identity on this personal account) — Terraform can't create
# its own first credential, so the terraform-google service account + its key
# are a one-time manual bootstrap, same category as cloudflare_api_token. See
# nix-config/CLAUDE.md's persona docs for how the Gemini key flows into
# kleinbem-secrets/personas/<name>.yaml's gemini_api_key field.
#
# credentials = base64-decoded google_service_account_key (sops). The google
# provider's `credentials` argument accepts raw JSON content directly — no
# file path needed, keeping the key out of any on-disk file this repo touches.
provider "google" {
  project     = "kleinbem-ai"
  credentials = base64decode(var.google_service_account_key)
}

# --- Project adoption (visibility only) -----------------------------------
# `kleinbem-ai` predates this block (hand-made via gcloud, see above).
# `google_project` cannot CREATE it — that needs
# roles/resourcemanager.projectCreator on an *organization*, and this is a
# bare personal account with no org. So this only ADOPTS the existing
# project, via the `import {}` block, purely so `tofu` state reflects reality
# and a stray `destroy` is refused.
#
# Deliberately minimal:
#   - billing_account omitted AND ignored. The provider only contacts the
#     Billing API when this field is set, and that read needs roles/billing.user
#     on the billing account (the terraform-google SA has no billing role).
#     Omitting it also stops Terraform trying to DETACH billing on apply.
#   - org_id / folder_id ignored: no parent on a personal-account project.
#   - name ignored: keeps the first import clean regardless of the exact
#     display name gcloud recorded. Set it to the real value from
#     `gcloud projects describe kleinbem-ai --format='value(name)'` and drop
#     it from ignore_changes only if you later want Terraform to own it —
#     which also needs roles/resourcemanager.projectEditor (or owner) on the
#     SA; roles/browser (already granted) is enough for import + read.
#   - deletion_policy = PREVENT + prevent_destroy: this project holds live
#     persona keys and the login OAuth client. Never let it be torn down.
#
# One-time adoption runs automatically on the next apply (declarative import,
# same mechanism as the R2 bucket in main.tf). Manual equivalent:
#   tofu import google_project.kleinbem_ai kleinbem-ai
import {
  to = google_project.kleinbem_ai
  id = "kleinbem-ai"
}

resource "google_project" "kleinbem_ai" {
  name       = "kleinbem-ai"
  project_id = "kleinbem-ai"

  deletion_policy = "PREVENT"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [billing_account, org_id, folder_id, name]
  }
}

# --- "Sign in with Google" client (MANUAL — no IaC path) ------------------
# NOT managed here, and cannot be: Google shut down the IAP OAuth Admin API
# (permanently, 2026-03-19) — it was the only programmatic route, and
# google_iap_brand / google_iap_client were removed from the provider
# (magic-modules #18679, 2026-08). There is no `google_oauth_client`
# resource. Created by hand in the Cloud console under this project,
# originally for kleinbem-auth (its own OAuth consent screen / client, app
# name "kleinbem.dev", authorized domain kleinbem.dev — created 2026-09).
#
# Reused as-is for Authentik's Google Source (authentik.tf) rather than
# minting a new client when kleinbem-auth was decommissioned 2026-09-21 —
# same client_id/secret, just an ADDITIONAL "Authorized redirect URI" added
# by hand alongside the original:
#   https://auth.kleinbem.dev/source/oauth/callback/google/
# The original https://login.kleinbem.dev/api/auth/callback/google entry
# was later removed by hand too (kleinbem-auth no longer runs, nothing
# uses it) — Authentik's is the only live redirect URI now.
#
# client_id / client_secret still live in
#   kleinbem-secrets/nix/per-container/kleinbem-auth.yaml
#     keys: google_client_id / google_client_secret
# (filename is a misnomer post-decommission — kept as-is rather than
# renamed, since renaming would also mean updating kleinbem-secrets/
# .sops.yaml's path-scoped rule and nix/tools/tf-apply.sh's decrypt list
# for a purely cosmetic gain). Read directly by tf-apply.sh (not through
# any NixOS host anymore) and exported as TF_VAR_kleinbem_auth_google_*
# for authentik.tf's authentik_source_oauth resource. The Facebook client
# mentioned in earlier versions of this comment was never actually set up
# (kleinbem-auth's own facebook_client_id/secret were always empty) — no
# Facebook Source exists in Authentik either.

# Both already enabled manually via gcloud during bootstrap (2026-08-07) —
# declared here so a from-scratch apply (new project) reproduces that state,
# and so `google_apikeys_key` below has an explicit dependency instead of an
# implicit ordering hope.
resource "google_project_service" "generativelanguage" {
  project            = "kleinbem-ai"
  service            = "generativelanguage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "apikeys" {
  project            = "kleinbem-ai"
  service            = "apikeys.googleapis.com"
  disable_on_destroy = false
}

# Google Drive API for the fleet's own rclone OAuth client (restic + secure
# backups to gdrive:backups, nix-config modules/nixos/backup.nix and nasbook's
# legacy backup container). Replaces rclone's shared client_id, which Google
# is retiring during 2026. The OAuth consent screen (External, *In
# production* — Testing mode expires refresh tokens after 7 days) and the
# Desktop-app OAuth client itself aren't Terraform-manageable for external
# apps (google_iap_* only covers internal/IAP clients), so those two are
# the manual first-credential step; the client_id/secret + token then live
# in `rclone_config` (kleinbem-secrets nix/shared.yaml).
resource "google_project_service" "drive" {
  project            = "kleinbem-ai"
  service            = "drive.googleapis.com"
  disable_on_destroy = false
}

# One API key per persona, restricted to the Generative Language API only —
# same narrow-scope principle as everything else persona-related (own
# signing key, own mailbox, now own API key). Add a new `google_apikeys_key`
# block here per persona rather than sharing one key across several.
resource "google_apikeys_key" "juan_gemini" {
  name         = "juan-gemini"
  display_name = "juan persona — Gemini API (hermes-juan)"
  project      = "kleinbem-ai"

  restrictions {
    api_targets {
      service = "generativelanguage.googleapis.com"
    }
  }

  depends_on = [google_project_service.generativelanguage, google_project_service.apikeys]
}

output "juan_gemini_api_key" {
  value     = google_apikeys_key.juan_gemini.key_string
  sensitive = true
}
