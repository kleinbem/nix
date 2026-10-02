# Per-host R2 credentials for the backup engine's `r2` destination
# (nix-config/modules/nixos/backup.nix → backup_r2_rclone_config in
# kleinbem-secrets/nix/per-host/<host>.yaml). One token per host so a single
# host's access can be revoked alone: drop it from the fleet's backup hosts
# and `just apply`.
#
# Why a separate root: minting API tokens needs "API Tokens: Edit", which is
# effectively account-admin (it can mint a token with any permission). Only
# this root holds that credential (cloudflare_token_minter_token) — the main
# infra/ root and its cloudflare_api_token never see it, and it's only
# decrypted when the backup-host list actually changes.
#
# Fails closed: the minter token has no default and must be non-empty, so a
# missing secret stops the run instead of planning to destroy every host's
# token (which would silently break all backups).
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_token_minter_token
}
