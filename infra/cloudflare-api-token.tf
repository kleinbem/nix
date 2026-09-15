# Terraform-managed replacement for the manually-created "nix-worksace-tofu"
# API token — this root's own operator token. Brings the manual
# dashboard-permission-edit ritual (see the "Requires:" comments in nearly
# every other .tf file here) under Terraform, so adding a permission for a
# new resource type is a config change + apply instead of a click.
#
# This grants "Account API Tokens: Edit" on itself, which the original token
# did NOT have (see cloudflare-r2.tf's comment on why that was withheld — a
# leaked token with this permission can mint new tokens with arbitrary
# scope). Discussed and accepted explicitly in favor of full IaC coverage.
#
# NOT an import of the existing token — the cloudflare_api_token resource in
# this provider doesn't support import at all (Cloudflare never returns a
# token's secret after creation, so there's no way to fully read an existing
# token's state). This CREATES A NEW, SEPARATE token instead. Cutover after
# first apply, all manual (nothing here does it for you):
#   1. `tofu output -raw infra_root_token_secret` (sensitive — read it, don't
#      commit it) and sops --set it as cloudflare_api_token in
#      kleinbem-secrets/infra/terraform.yaml.
#   2. Re-run whatever you were doing (tofu plan/apply for something else)
#      using the NEW value, confirm it actually works.
#   3. Only once confirmed: delete "nix-worksace-tofu" by hand in the
#      dashboard. Terraform never owned it, so it won't clean it up for you.
#
# permission_groups are hardcoded IDs, not the
# `data.cloudflare_api_token_permission_groups` data source — that data
# source calls Cloudflare's user-level endpoint (`/user/tokens/
# permission_groups`), which an Account-scoped token can never authenticate
# against (error 9109, "Valid user-level authentication not found") no
# matter what permissions it holds. IDs below were read directly from the
# account-scoped endpoint instead: `GET /accounts/{account_id}/tokens/
# permission_groups`, called with nix-worksace-tofu's own token (2026-09-15)
# — these are stable, global Cloudflare constants, not account-specific, so
# they don't need re-verifying if this file is copied elsewhere. One name
# collision worth noting: "Access: Apps and Policies Read/Write" each exist
# as two different IDs — an account-scoped variant ("Can read/edit
# Cloudflare Access applications and policies") and a zone-scoped one
# ("...zone resources", for the older per-zone Access product). This repo's
# cloudflare_zero_trust_access_application/policy resources are account-
# level, so the account-scoped IDs are used below.

resource "cloudflare_api_token" "infra_root" {
  name = "nix-infra-tofu"

  # kleinbem.dev zone
  policy {
    permission_groups = [
      "74e1036f577a48528b78d2413b40538d", # Dynamic URL Redirects Write
      "d8e12db741544d1586ec1d6f5d3c7786", # Dynamic URL Redirects Read
      "fb6778dc191143babbfaa57993f1d275", # Zone WAF Write
      "c8fed203ed3043cba015a93ad1616f1f", # Zone Read
      "82e64a83756745bbbb1c9c2701bf816b", # DNS Read
      "4755a26eedb94da69e1066d98aa820be", # DNS Write
    ]
    resources = {
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.main.id}" = "*"
    }
  }

  # Entire account
  policy {
    permission_groups = [
      "037b9e348b3b42d4b46ea2fcb1cfb3e7", # Cloudflare One Connector: cloudflared Write
      "c1968d31028d4239976ec3bc4750bbf6", # Cloudflare One Connector: cloudflared Read
      "8d28297797f24fb8a0c332fe0866ec89", # Pages Write
      "e247aedd66bd41cc9193af0213416666", # Pages Read
      "bf7481a1826f439697cb59a20b22293e", # Workers R2 Storage Write
      "b4992e1108244f5d8bfbd5744320c2e1", # Workers R2 Storage Read
      "b89a480218d04ceb98b4fe57ca29dc1f", # Account Analytics Read
      "1e13c5124ca64b72b1969a67e8829049", # Access: Apps and Policies Write (account-scoped)
      "7ea222f6d5064cfa89ea366d7c1fee89", # Access: Apps and Policies Read (account-scoped)
      "755c05aa014b4f9ab263aa80b8167bd8", # Turnstile Sites Write
      "5d78fd7895974fd0bdbbbb079482721b", # Turnstile Sites Read
      "5bc3f8b21c554832afc660159ab75fa4", # Account API Tokens Write — self-management, new
      "eb56a6953c034b9d97dd838155666f06", # Account API Tokens Read — self-management, new
    ]
    resources = {
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    }
  }
}

output "infra_root_token_secret" {
  description = "New token's secret — sensitive. `tofu output -raw infra_root_token_secret`, then sops --set it, never paste it into chat or commit it."
  value       = cloudflare_api_token.infra_root.value
  sensitive   = true
}
