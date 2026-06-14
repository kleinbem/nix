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
resource "cloudflare_zero_trust_tunnel_cloudflared" "nixos_nvme" {
  account_id = var.cloudflare_account_id
  name       = "nixos-nvme"
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
  content = "${cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# Route apex domain (@) to argo tunnel CNAME
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.nixos_nvme.id
}

# R2 bucket that holds the github-config tofu remote state. Provisioned from
# here (local state) to avoid a chicken-and-egg: a config can't store its own
# state in a bucket it is also creating. Requires the cloudflare_api_token to
# have "Workers R2 Storage: Edit" permission.
resource "cloudflare_r2_bucket" "tofu_state" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-tofu-state"
}

output "tofu_state_bucket" {
  value = cloudflare_r2_bucket.tofu_state.name
}

