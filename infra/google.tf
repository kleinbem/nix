# GCP project `kleinbem-ai`: per-persona Gemini keys and the Google OAuth client
# Authentik uses (authentik.tf). The project and the terraform-google service
# account key were made by hand with gcloud (no org on a personal account).
# `credentials` takes the JSON content, so the key never touches disk.
provider "google" {
  project     = "kleinbem-ai"
  credentials = base64decode(var.google_service_account_key)
}

# --- Project adoption (visibility only) -----------------------------------
# Adopted, not created: the project was made by hand (see above). Imported so
# state matches reality.
# billing_account stays unset and ignored: setting it makes the provider call the
# Billing API, which the SA has no role for. Owning `name` would need
# projectEditor on the SA; roles/browser covers import + read.
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
# No API exists for OAuth clients any more (the IAP OAuth Admin API is gone), so
# this was made by hand in the Cloud console. Its only redirect URI is
#   https://auth.kleinbem.dev/source/oauth/callback/google/
# tf-apply.sh reads client_id/secret from
# kleinbem-secrets/nix/per-container/kleinbem-auth.yaml and exports them as
# TF_VAR_kleinbem_auth_google_*.

# Declared so a fresh project gets them and google_apikeys_key can depend on them.
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

# Drive API for the fleet's own rclone OAuth client (gdrive backups). The consent
# screen and the Desktop OAuth client are manual; keep the screen "In production",
# since Testing mode expires refresh tokens after 7 days. Credentials live in
# `rclone_config` (kleinbem-secrets nix/shared.yaml).
resource "google_project_service" "drive" {
  project            = "kleinbem-ai"
  service            = "drive.googleapis.com"
  disable_on_destroy = false
}

# One key per persona, limited to the Generative Language API. Add a block per
# persona rather than sharing a key.
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
