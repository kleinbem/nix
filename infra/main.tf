terraform {
  # OpenTofu: state encryption (1.7) and the s3 backend's use_lockfile (1.10).
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2026.0"
    }
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.3"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Only distributes Actions secrets to the CI repos; repo settings belong to
# github-config. Uses the account-wide kleinbem GitHub App, so a new repo needs
# no token change.
provider "github" {
  owner = "kleinbem"
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_private_key # PEM contents, despite the name
  }
}

# The same App on the kleinbem-dev organization (its own installation id):
# for the secrets of repos that moved there, local.org_ci_secrets.
provider "github" {
  alias = "org"
  owner = "kleinbem-dev"
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_org_installation_id
    pem_file        = var.github_app_private_key
  }
}

data "cloudflare_zone" "main" {
  name = "kleinbem.dev"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "core_pi" {
  account_id = var.cloudflare_account_id
  name       = "core-pi"
  secret     = var.cloudflare_tunnel_secret

  # The API never returns the secret, so without this every plan would replace
  # the live tunnel. To rotate, drop ignore_changes for one apply.
  lifecycle {
    ignore_changes = [secret]
  }
}

# Route wildcard domain to the argo tunnel CNAME
resource "cloudflare_record" "wildcard" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.core_pi.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# Route apex domain (@) to argo tunnel CNAME
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.core_pi.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.core_pi.id
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme
  to   = cloudflare_zero_trust_tunnel_cloudflared.core_pi
}

# Bucket holding tofu state for this root, the sub-roots and github-config. Made by hand in the
# dashboard (this root's backend lives in it, so tofu can't create it) and
# adopted by the import block. Needs "Workers R2 Storage: Edit" on the token.
import {
  to = cloudflare_r2_bucket.tofu_state
  # Import ids can't be sensitive; the account id only shows in local plan output.
  id = "${nonsensitive(var.cloudflare_account_id)}/kleinbem-tofu-state"
}

resource "cloudflare_r2_bucket" "tofu_state" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-tofu-state"

  # Holds the state that manages it; destroying it would orphan every root.
  lifecycle {
    prevent_destroy = true
  }
}

output "tofu_state_bucket" {
  value = cloudflare_r2_bucket.tofu_state.name
}

