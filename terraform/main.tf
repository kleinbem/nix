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

# Create the Zero Trust Tunnel
resource "cloudflare_tunnel" "nixos_nvme" {
  account_id = var.cloudflare_account_id
  name       = "nixos-nvme"
  secret     = var.cloudflare_tunnel_secret
}

# Route wildcard domain to the argo tunnel CNAME
resource "cloudflare_record" "wildcard" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  value   = "${cloudflare_tunnel.nixos_nvme.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# Route apex domain (@) to argo tunnel CNAME
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  value   = "${cloudflare_tunnel.nixos_nvme.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

output "tunnel_id" {
  value = cloudflare_tunnel.nixos_nvme.id
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

