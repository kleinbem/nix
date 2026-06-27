# Garage object-storage CONTROL PLANE as code (OpenTofu).
#
# BOUNDARY (mirrors the NixOS <-> Tofu split we use for NetBird):
#   - NixOS owns the DAEMON + node config (services.garage in
#     nix-config/hosts/nixos-nvme/garage.nix) and the one-time cluster LAYOUT
#     (`garage layout assign/apply` — node lifecycle, run once via CLI; a node
#     with no layout can't store objects, so do it BEFORE applying this root).
#   - This root owns the S3 CONTROL PLANE: buckets, access keys, and the
#     key->bucket permissions. It talks to the Garage Admin API (v2) with the
#     admin token, exactly like infra/netbird talks to the NetBird API.
#
# Provider is COMMUNITY (jkossis/garage), v1.0.x — pinned, review on upgrades
# (same diligence as the netbird provider). It is NOT on the OpenTofu registry,
# so the source is fully qualified to the Terraform registry (OpenTofu pulls it
# from there). Requires Garage Admin API v2 (Garage >= 0.9.0; we run v2.3.0).
# Schema (bucket/key/permission attrs) verified against v1.0.4 via `just schema`.
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
