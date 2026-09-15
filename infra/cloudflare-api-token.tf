# Self-management of this root's own cloudflare_api_token ("nix-worksace-tofu"
# — yes, that's a typo in the real token name, kept verbatim so Terraform
# doesn't try to rename it on import) — bringing the manual
# dashboard-permission-edit ritual (see the "Requires:" comments in nearly
# every other .tf file here) under Terraform, so adding a permission for a
# new resource type is a config change + apply instead of a click.
#
# This grants the token "Account API Tokens: Edit" on itself, which it did
# NOT have before (see cloudflare-r2.tf's comment on why that was withheld —
# a leaked token with this permission can mint new tokens with arbitrary
# scope, a real escalation beyond whatever this token itself can already
# do). That tradeoff was discussed and accepted explicitly in favor of full
# IaC coverage — see git history for that conversation.
#
# Token inventory / why this one: this account actually has 4 API tokens.
# `nix-worksace-tofu` (this one) is the real one nix/infra's Terraform root
# authenticates as — its permission set matches every resource in this
# root's .tf files exactly. `homelab-infra` is an older, User-scoped token
# (Cloudflare recommends Account tokens) with a strict subset of these
# permissions — superseded, to be retired once this is confirmed working.
# `kleinbem-site-pages-deploy` (Pages only, GitHub Actions) and the R2
# state-backend/backup credentials are deliberately separate tokens for
# separate trust boundaries (narrower blast radius for CI-exposed and
# host-materialized secrets) — not folded into this one.
#
# Every permission-group name and resource scope below was copied verbatim
# from the token's own dashboard summary (2026-09-15), not reconstructed
# from guesses — this file's first two drafts got that wrong in both
# directions and this version replaces them.
#
# SAFETY PROCEDURE — read before running anything:
#   1. terraform import cloudflare_api_token.infra_root <token_id>
#      (the ID, not the secret — Cloudflare dashboard -> My Profile ->
#      API Tokens -> nix-worksace-tofu -> the ID is on its detail page/URL)
#   2. Run `tofu plan` and READ THE DIFF before applying anything. It
#      should show NO changes at all — every permission below already
#      exists on the live token (you added Turnstile + API Tokens manually
#      already). A clean no-diff plan is exactly the goal: it proves this
#      file is an accurate mirror of reality, safe to manage going forward.

data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "infra_root" {
  name = "nix-worksace-tofu"

  # kleinbem.dev zone
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["Dynamic URL Redirects Write"],
      data.cloudflare_api_token_permission_groups.all.zone["Dynamic URL Redirects Read"],
      data.cloudflare_api_token_permission_groups.all.zone["Zone WAF Write"],
      data.cloudflare_api_token_permission_groups.all.zone["Zone Read"],
      data.cloudflare_api_token_permission_groups.all.zone["DNS Read"],
      data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.main.id}" = "*"
    }
  }

  # Entire account (kleinbem's Cloudflare account)
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.account["Cloudflare One Connector: cloudflared Write"],
      data.cloudflare_api_token_permission_groups.all.account["Cloudflare One Connector: cloudflared Read"],
      data.cloudflare_api_token_permission_groups.all.account["Pages Write"],
      data.cloudflare_api_token_permission_groups.all.account["Pages Read"],
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Write"],
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Read"],
      data.cloudflare_api_token_permission_groups.all.account["Account Analytics Read"],
      data.cloudflare_api_token_permission_groups.all.account["Access: Apps and Policies Write"],
      data.cloudflare_api_token_permission_groups.all.account["Access: Apps and Policies Read"],
      data.cloudflare_api_token_permission_groups.all.account["Turnstile Sites Write"],
      data.cloudflare_api_token_permission_groups.all.account["Turnstile Sites Read"],
      data.cloudflare_api_token_permission_groups.all.account["Account API Tokens Write"], # self-management, new
      data.cloudflare_api_token_permission_groups.all.account["Account API Tokens Read"],  # self-management, new
    ]
    resources = {
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    }
  }
}
