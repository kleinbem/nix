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

variable "attic_push_token" {
  type        = string
  sensitive   = true
  description = "Attic cache push token, distributed as the ATTIC_PUSH_TOKEN Actions secret."
}

# --- Persona-fleet mail infrastructure ---

variable "mail_host_ip" {
  type        = string
  description = "Public IPv4 of the host serving Stalwart (referenced by mail.kleinbem.dev A record). Stalwart's SMTP port can't be Cloudflare-proxied."
}
