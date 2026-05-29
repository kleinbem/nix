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

# --- GitHub ----------------------------------------------------------------

variable "github_tf_token" {
  type        = string
  description = "Admin PAT used by the github provider to manage repos/secrets (classic: repo + workflow). Not mintable via API — created by hand, stored in sops."
  sensitive   = true
}

variable "attic_push_token" {
  type        = string
  description = "Attic cache push token; distributed to repos as the ATTIC_PUSH_TOKEN Actions secret."
  sensitive   = true
}

variable "github_ci_pat" {
  type        = string
  description = "CI automation PAT (lock-update PRs, workflow dispatch); distributed to repos as the GH_PAT Actions secret."
  sensitive   = true
}
