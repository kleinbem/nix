# NetBird control plane: groups, policies, setup keys, routes, DNS and peer
# expiry flags. Peers self-enroll from NixOS (netbird-autojoin in nix-config
# modules/nixos/networking.nix); this root never creates them.
# The provider is unsigned on the registry; review it on upgrades.
terraform {
  # OpenTofu: state encryption (1.7) and the s3 backend's use_lockfile (1.10).
  required_version = ">= 1.10"

  required_providers {
    netbird = {
      source = "netbirdio/netbird"
      # Pinned exactly — provider is pre-1.0, so minor bumps may break schema.
      version = "0.0.11"
    }
  }
}

provider "netbird" {
  # NetBird Cloud by default; set TF_VAR_netbird_management_url for self-hosted.
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}
