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

variable "github_ci_pat" {
  type        = string
  sensitive   = true
  description = "CI automation PAT distributed as the GH_PAT Actions secret (Contents R/W + Pull requests R/W on nix-packages for the Antigravity auto-merge workflow)."
}

variable "attic_push_token" {
  type        = string
  sensitive   = true
  description = "Attic cache push token, distributed as the ATTIC_PUSH_TOKEN Actions secret."
}
