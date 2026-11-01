# NetBird control plane: groups, policies, setup keys, routes, DNS and peer
# expiry flags. Peers self-enroll from NixOS (netbird-autojoin in nix-config
# modules/nixos/networking.nix); this root never creates them.
# The provider is unsigned on the registry; review it on upgrades.
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
  # NetBird Cloud by default; set TF_VAR_netbird_management_url for self-hosted.
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}
