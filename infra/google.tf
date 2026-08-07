# Google Cloud — currently scoped to exactly one thing: Gemini API keys for
# AI personas (juan first). Project `kleinbem-ai` was created manually via
# gcloud (2026-08-07, no org/Cloud Identity on this personal account) —
# Terraform can't create its own first credential, so the terraform-google
# service account + its key are a one-time manual bootstrap, same category
# as cloudflare_api_token. See nix-config/CLAUDE.md's persona docs for how
# the resulting key flows into kleinbem-secrets/personas/<name>.yaml's
# gemini_api_key field.
#
# credentials = base64-decoded google_service_account_key (sops). The google
# provider's `credentials` argument accepts raw JSON content directly — no
# file path needed, keeping the key out of any on-disk file this repo touches.
provider "google" {
  project     = "kleinbem-ai"
  credentials = base64decode(var.google_service_account_key)
}

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
