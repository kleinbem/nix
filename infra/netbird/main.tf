# NetBird control-plane as code (OpenTofu).
#
# BOUNDARY (mirrors github-config ↔ infra split):
#   - NixOS owns the DATA PLANE: peer enrollment via `netbird up` (the
#     netbird-autojoin oneshot in modules/nixos/networking.nix). This root does
#     NOT manage peers — they self-register.
#   - This root owns the CONTROL PLANE: groups, access policies, setup keys,
#     (later) nameservers / routes / posture checks.
#
# ⚠️ PROVIDER SCHEMA: the resource/attribute names below are a best-effort
#    starting point. After `just init`, run `tofu providers schema -json | jq`
#    (or read the registry docs for netbirdio/netbird) and reconcile names
#    before the first apply. `tofu plan` is the source of truth here.
terraform {
  required_providers {
    netbird = {
      # Official provider: https://registry.terraform.io/providers/netbirdio/netbird
      source = "netbirdio/netbird"
      # Pin after `tofu init` selects a version (then commit .terraform.lock.hcl).
      version = "~> 0.1"
    }
  }
}

provider "netbird" {
  # NetBird Cloud API. For a self-hosted management server, override via
  # TF_VAR_netbird_management_url. (Peer FQDNs are *.netbird.cloud → Cloud SaaS.)
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}
