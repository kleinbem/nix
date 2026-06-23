# NetBird control-plane as code (OpenTofu).
#
# BOUNDARY (mirrors github-config ↔ infra split):
#   - NixOS owns the DATA PLANE: peer enrollment via `netbird up` (the
#     netbird-autojoin oneshot in modules/nixos/networking.nix). This root does
#     NOT manage peers — they self-register.
#   - This root owns the CONTROL PLANE: groups, access policies, setup keys,
#     (later) nameservers / routes / posture checks.
#
# Resource/attribute names below were reconciled against the netbirdio/netbird
# provider schema (v0.0.9, `tofu providers schema -json`). Note: this provider
# is UNSIGNED on the registry (no GPG keys) — early-stage; review on upgrades.
# Still gated on creds/token before a real apply; `tofu plan` is the final word.
terraform {
  required_providers {
    netbird = {
      source = "netbirdio/netbird"
      # Pinned exactly — provider is pre-1.0, so minor bumps may break schema.
      version = "0.0.9"
    }
  }
}

provider "netbird" {
  # NetBird Cloud API. For a self-hosted management server, override via
  # TF_VAR_netbird_management_url. (Peer FQDNs are *.netbird.cloud → Cloud SaaS.)
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}
