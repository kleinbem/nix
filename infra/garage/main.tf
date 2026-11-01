# Garage buckets, keys and permissions via the Admin API v2. NixOS owns the
# daemon (nix-config/hosts/nixos-nvme/garage.nix): run `garage layout
# assign/apply` once first, or the node can't store objects. The provider is
# not on the OpenTofu registry, hence the full source; check `just schema`
# before bumping it.
terraform {
  required_providers {
    garage = {
      source  = "registry.terraform.io/jkossis/garage"
      version = "1.0.4"
    }
  }
}

provider "garage" {
  endpoint = var.garage_endpoint
  token    = var.garage_admin_token
}
