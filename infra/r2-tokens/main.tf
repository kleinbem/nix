# Cloudflare API tokens minted by IaC:
#   - tokens.tf: per-host R2 credentials for the backup engine's `r2`
#     destination (nix-config/modules/nixos/backup.nix → backup_r2_rclone_config
#     in kleinbem-secrets/nix/per-host/<host>.yaml). One token per host so a
#     single host's access can be revoked alone: drop it from the fleet's
#     backup hosts and `just apply`.
#   - acme-dns.tf: Caddy's DNS-01 token on core-pi (publicly trusted certs for
#     mesh-only names), synced into kleinbem-secrets/nix/per-host/core-pi.yaml.
#   - public-cache.tf: CI credentials for the public cache bucket
#     (cache.kleinbem.dev), synced into kleinbem-secrets/infra/terraform.yaml.
#   - r2-budget.tf: the R2 budget watchdog's token (kleinbem/nix's r2-budget
#     workflow), synced into kleinbem-secrets/infra/terraform.yaml.
#
# Why a separate root: minting API tokens needs "API Tokens: Edit", which is
# effectively account-admin (it can mint a token with any permission). Only
# this root holds that credential (cloudflare_token_minter_token) — the main
# infra/ root and its cloudflare_api_token never see it, and it's only
# decrypted when the backup-host list or a minted token's scope changes.
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
