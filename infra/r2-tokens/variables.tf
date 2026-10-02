variable "cloudflare_token_minter_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Cloudflare API token with ONLY User → API Tokens: Edit, client-IP
    restricted. Bootstrapped once by hand (dashboard → My Profile → API
    Tokens → Create Custom Token) and stored in
    kleinbem-secrets/infra/terraform.yaml as cloudflare_token_minter_token.
    Nothing outside this root uses it.
  EOT

  validation {
    condition     = length(var.cloudflare_token_minter_token) > 0
    error_message = "cloudflare_token_minter_token is empty — refusing to run (an empty minter would plan to destroy every host's backup token)."
  }
}

variable "cloudflare_account_id" {
  type        = string
  sensitive   = true
  description = "Cloudflare account id (kleinbem-secrets/nix/per-host/core-pi.yaml)."
}

variable "backup_bucket" {
  type        = string
  default     = "kleinbem-backup"
  description = "R2 bucket the tokens are scoped to. Owned by the main infra/ root (cloudflare-r2.tf); not referenced across roots, so keep the name in sync."
}
