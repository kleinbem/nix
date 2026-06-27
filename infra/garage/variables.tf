variable "garage_admin_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Garage Admin API bearer token — the same GARAGE_ADMIN_TOKEN injected into the
    garage service via sops. Stored in nix-secrets/secrets.yaml as
    `garage_admin_token`; the Justfile sources it into TF_VAR_garage_admin_token.
  EOT
}

variable "garage_endpoint" {
  type        = string
  default     = "http://127.0.0.1:3903"
  description = <<-EOT
    Garage Admin API endpoint. Default is the loopback admin listener on the host
    running garage (nixos-nvme) — so run tofu THERE, or point this at the host's
    NetBird/bridge address when applying from elsewhere.
  EOT
}
