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
