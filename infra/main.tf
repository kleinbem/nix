terraform {
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
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Only used here to DISTRIBUTE Actions secrets to the nix CI repos (values come
# from sops). Repo settings/rulesets/labels are owned by the github-config repo.
provider "github" {
  owner = "kleinbem"
  token = var.github_tf_token
}

data "cloudflare_zone" "main" {
  name = "kleinbem.dev"
}

# Create the Zero Trust Tunnel (renamed from the deprecated `cloudflare_tunnel`
# resource type — same underlying API object, same schema, just the v4.x rename
# from "tunnel" to "zero_trust_tunnel_cloudflared" namespace).
resource "cloudflare_zero_trust_tunnel_cloudflared" "core_pi" {
  account_id = var.cloudflare_account_id
  name       = "core-pi"
  secret     = var.cloudflare_tunnel_secret

  # The Cloudflare API doesn't return the tunnel secret on read, so after
  # `tofu import` the state has `secret = null` while the config has the sops
  # value. Without ignore_changes, every plan would mark the resource as
  # "ForceNew on secret" and propose destroying + recreating the live tunnel.
  # We trust the existing secret in Cloudflare; if it ever needs rotation,
  # remove this ignore_changes briefly to apply the new value.
  lifecycle {
    ignore_changes = [secret]
  }
}

# Note: `moved {}` blocks don't work for this rename because the cloudflare
# provider v4.x explicitly refuses cross-type state moves. The state was
# migrated via `tofu state rm` + `tofu import` (run via
# `scripts/tf-apply.sh --migrate-tunnel`) — one-shot operation, no live
# tunnel touch.

# Route wildcard domain to the argo tunnel CNAME
resource "cloudflare_record" "wildcard" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  # `content` replaces the deprecated `value` argument (provider v4.x).
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

# R2 bucket that holds tofu remote state: github-config's AND (since the
# backend.tf migration) this root's own `infra.tfstate`. Originally provisioned
# from local state to dodge the chicken-and-egg of a config storing state in a
# bucket it creates. Requires the cloudflare_api_token to have "Workers R2
# Storage: Edit" permission.
# The bucket was created MANUALLY in the dashboard (R2 activation + bucket +
# scoped API token are a hand-bootstrap: this root's own backend lives in the
# bucket, so tofu couldn't create it first). This import block adopts it into
# state on the first apply after migration; once adopted it's a no-op.
import {
  to = cloudflare_r2_bucket.tofu_state
  # nonsensitive(): import ids may not be sensitive, and the account id's
  # sensitivity taints the whole interpolation. The id never appears in
  # committed files — only in plan output on this machine.
  id = "${nonsensitive(var.cloudflare_account_id)}/kleinbem-tofu-state"
}

resource "cloudflare_r2_bucket" "tofu_state" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-tofu-state"

  # This bucket now holds the state that manages it. Destroying it would
  # orphan every root that backs onto it — refuse at plan time.
  lifecycle {
    prevent_destroy = true
  }
}

output "tofu_state_bucket" {
  value = cloudflare_r2_bucket.tofu_state.name
}

