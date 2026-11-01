# Cloudflare API tokens minted by IaC: per-host backup R2 creds (tokens.tf, one per
# host so each can be revoked alone), Caddy's DNS-01 token (acme-dns.tf), public
# cache CI creds and the r2-budget token. sync-secrets.sh copies them into sops.
# A separate root because "API Tokens: Edit" is effectively account-admin. The
# minter token has no default, so a missing secret stops the run instead of
# planning to destroy every token.
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
