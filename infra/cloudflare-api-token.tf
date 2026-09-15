# Self-management of this root's own cloudflare_api_token ("homelab-infra")
# — bringing the manual dashboard-permission-edit ritual (see the
# "Requires:" comments in nearly every other .tf file here) under Terraform,
# so adding a permission for a new resource type is a config change + apply
# instead of a click.
#
# This deliberately grants the token "API Tokens: Edit" on itself, which it
# did NOT have before (see cloudflare-r2.tf's comment on why that was
# withheld — a leaked token with this permission can mint NEW tokens with
# arbitrary scope, a real escalation beyond whatever this token itself can
# already do). That tradeoff was discussed and accepted explicitly in favor
# of full IaC coverage — see git history for that conversation.
#
# The policy list below is reconstructed from the token's own dashboard
# summary (pasted 2026-09-15), NOT from this repo's scattered "Requires:"
# comments — an earlier draft tried that and would have both dropped real
# grants (Account Settings, Zone Settings, Zone:Read, SSL and Certificates)
# and added ones the live token doesn't actually have/need (Dynamic URL
# Redirects, Pages, Account Analytics — evidently covered some other way,
# since those resources already apply successfully without them). Scope is
# "All accounts" / "All zones" on the real token, not a single account/zone
# ID, so the resource keys below use the account/zone wildcard form.
#
# SAFETY PROCEDURE — read before running anything:
#   1. terraform import cloudflare_api_token.infra_root <token_id>
#      (the ID, not the secret — Cloudflare dashboard -> My Profile ->
#      API Tokens -> homelab-infra -> the ID is on its detail page/URL)
#   2. Run `tofu plan` and READ THE DIFF before applying anything. It
#      should show only the two new grants (Turnstile Edit, API Tokens
#      Edit) being added — nothing else added or removed. If anything else
#      shows up, stop and say what it is before applying.

data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "infra_root" {
  name = "homelab-infra"

  # All accounts — matches the live token's existing account-level grants,
  # plus Turnstile Edit (new, for cloudflare-turnstile.tf).
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Write"],
      data.cloudflare_api_token_permission_groups.all.account["Cloudflare Tunnel Write"],
      data.cloudflare_api_token_permission_groups.all.account["Account Settings Write"],
      data.cloudflare_api_token_permission_groups.all.account["Account Settings Read"],
      data.cloudflare_api_token_permission_groups.all.account["Access: Apps and Policies Write"],
      data.cloudflare_api_token_permission_groups.all.account["Turnstile Write"], # new
    ]
    resources = {
      "com.cloudflare.api.account.*" = "*"
    }
  }

  # All zones — matches the live token's existing zone-level grants exactly.
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["Zone WAF Write"],
      data.cloudflare_api_token_permission_groups.all.zone["Zone Settings Write"],
      data.cloudflare_api_token_permission_groups.all.zone["Zone Read"],
      data.cloudflare_api_token_permission_groups.all.zone["SSL and Certificates Write"],
      data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.*" = "*"
    }
  }

  # Self-management — the whole point of this resource. User-scoped (API
  # tokens belong to the account owner, not a zone/account object), so this
  # policy's resource key is a fixed "com.cloudflare.api.user.*" rather than
  # an ID substitution — a token only ever acts as its own creating user.
  # If this specific block errors on apply, that's the part most likely to
  # need a fix — share the exact error message.
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.user["API Tokens Write"], # new
    ]
    resources = {
      "com.cloudflare.api.user.*" = "*"
    }
  }
}
