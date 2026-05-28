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
