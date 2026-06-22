variable "netbird_api_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    NetBird Management API personal access token (NOT a setup key). Create it in
    the NetBird console under your user → Personal Access Tokens with permission
    to manage groups/policies/setup-keys. Store it in nix-secrets/secrets.yaml as
    `netbird_api_token`; the Justfile sources it via sops into TF_VAR_netbird_api_token.
  EOT
}

variable "netbird_management_url" {
  type        = string
  default     = "https://api.netbird.io"
  description = "NetBird management API base URL. Override for a self-hosted server."
}
