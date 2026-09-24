variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token with Zero Trust and DNS permissions"
  sensitive   = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID"
  sensitive   = true
}

variable "cloudflare_pages_deploy_token" {
  type        = string
  sensitive   = true
  description = "Narrowly-scoped (Cloudflare Pages: Edit only) API token for kleinbem-site's CI to run `wrangler pages deploy`. Deliberately separate from cloudflare_api_token — a leaked CI secret shouldn't be able to touch DNS/WAF/Zero Trust. Distributed as the CLOUDFLARE_PAGES_DEPLOY_TOKEN Actions secret via github-secrets.tf."
}

variable "cloudflare_tunnel_secret" {
  type        = string
  description = "A 32-byte base64-encoded secret key for the tunnel"
  sensitive   = true
}

# --- GitHub (secret distribution only; repo config lives in github-config) ---

variable "github_tf_token" {
  type        = string
  sensitive   = true
  description = "Fine-grained PAT for distributing Actions secrets to the nix CI repos (Secrets R/W + Metadata R on nix, nix-config, nix-packages)."
}

variable "github_app_id" {
  type        = string
  sensitive   = true
  description = "GitHub App ID, distributed as the APP_ID Actions secret. Workflows mint a short-lived installation token via actions/create-github-app-token instead of using a long-lived PAT. Required App permissions: Contents R/W + Pull requests R/W on kleinbem/nix-config and kleinbem/nix-packages."
}

variable "github_app_private_key" {
  type        = string
  sensitive   = true
  description = "GitHub App private key (PEM), distributed as the APP_PRIVATE_KEY Actions secret. Used by actions/create-github-app-token to mint installation tokens at workflow runtime."
}

variable "github_app_installation_id" {
  type        = string
  sensitive   = true
  description = "Installation ID of the GitHub App on the kleinbem account, distributed as the APP_INSTALLATION_ID Actions secret. github-config's tofu provider authenticates with `app_auth {}` (env: GITHUB_APP_ID / GITHUB_APP_INSTALLATION_ID / GITHUB_APP_PEM_FILE) instead of a PAT, and that path needs the installation ID explicitly."
}

variable "attic_push_token" {
  type        = string
  sensitive   = true
  description = "Attic cache push token, distributed as the ATTIC_PUSH_TOKEN Actions secret."
}

variable "netbird_setup_key" {
  type        = string
  sensitive   = true
  description = "NetBird setup key, distributed as the NETBIRD_SETUP_KEY Actions secret. Used by hosted CI runners to bring up the NetBird WireGuard tunnel and push large NARs to Attic without hitting Cloudflare's 100 MiB upload limit. Being retired in favour of netbird_setup_key_ephemeral (kept as a fallback until CI is confirmed green on the ephemeral key)."
}

variable "netbird_setup_key_ephemeral" {
  type        = string
  sensitive   = true
  default     = ""
  description = "EPHEMERAL NetBird setup key (peers auto-deleted ~10 min after going offline), distributed as the NETBIRD_SETUP_KEY_EPHEMERAL Actions secret. Minted by infra/netbird/ (setup-keys.tf) and fanned here via sops. CI workflows prefer it over netbird_setup_key so one-shot runners stop accumulating against the peer cap. Empty default keeps apply working before the key is minted."
}

variable "ntfy_alert_topic" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Secret ntfy topic name (sops: ntfy_alert_topic), distributed as the NTFY_ALERT_TOPIC Actions secret. CI posts human-facing failure alerts to it (e.g. build-all's blocking container-factory eval — typically an insecure re-ack after a nixpkgs bump). Deliberately separate from ntfy_deploy_topic: that one is machine-consumed (any message triggers host upgrade polls), this one is for a human's phone. Empty default keeps apply working before the topic is minted (alert steps in CI skip when the secret is empty)."
}

variable "ntfy_deploy_topic" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Secret ntfy topic name (sops: ntfy_deploy_topic), distributed as the NTFY_DEPLOY_TOPIC Actions secret. promote-production publishes 'production → SHA' to it after advancing the tag; hosts running my.deploy.autoUpgrade.ntfy long-poll it and upgrade immediately. The unguessable name is the access control on the public ntfy.kleinbem.dev vhost. Empty default keeps apply working before the topic is minted (the publish step in CI skips when the secret is empty)."
}

# --- Google Cloud (currently: Gemini API keys for AI personas only) ---

variable "google_service_account_key" {
  type        = string
  sensitive   = true
  description = "Base64-encoded JSON key for the terraform-google service account (project kleinbem-ai, roles/serviceusage.apiKeysAdmin). Bootstrap credential — created manually via gcloud (2026-08-07), not itself Terraform-managed, same as cloudflare_api_token."
}

variable "r2_state_access_key_id" {
  type        = string
  sensitive   = true
  description = "Cloudflare R2 access key ID for state backend"
}

variable "r2_state_secret_access_key" {
  type        = string
  sensitive   = true
  description = "Cloudflare R2 secret access key for state backend"
}

variable "authentik_api_token" {
  type        = string
  sensitive   = true
  description = "Authentik bootstrap API token (akadmin) — same value NixOS's authentik.nix uses to bootstrap the instance (kleinbem-secrets/nix/per-container/authentik.yaml, AUTHENTIK_BOOTSTRAP_TOKEN). Bootstrap credential, not itself Terraform-managed."
}

variable "kleinbem_site_session_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Symmetric key kleinbem-site's own Pages Functions use to sign its session cookie after the OIDC exchange completes (kleinbem-secrets/infra/terraform.yaml). Generated with `openssl rand -hex 32` — unrelated to Authentik's own client_secret; kept separate so rotating one never invalidates the other. Empty default keeps apply working before the key is minted."
}

variable "kleinbem_auth_google_client_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Reused, not new: the same Google OAuth 2.0 Web Client that kleinbem-auth's own Google sign-in used (kleinbem-secrets/nix/per-container/kleinbem-auth.yaml, google_client_id), confirmed live 2026-09-21 to still be a real, populated credential on core-pi. Wiring it into Authentik as a Source needs its own additional 'Authorized redirect URI' added on the SAME Google Cloud OAuth client (Authentik's callback path differs from better-auth's) — see authentik_source_oauth.google's callback_uri output for the exact value to add. Empty default keeps apply working before this variable's first real wiring."
}

variable "kleinbem_auth_google_client_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Paired with kleinbem_auth_google_client_id above — same reused Google OAuth client, same source file/key (google_client_secret)."
}
