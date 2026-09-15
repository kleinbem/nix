# Self-management of this root's own cloudflare_api_token — bringing the
# manual dashboard-permission-edit ritual (see the "Requires:" comments in
# nearly every other .tf file here) under Terraform, so adding a permission
# for a new resource type is a config change + apply instead of a click.
#
# This deliberately grants the token "API Tokens: Edit" on itself, which it
# did NOT have before (see cloudflare-r2.tf's comment on why that was
# withheld — a leaked token with this permission can mint NEW tokens with
# arbitrary scope, a real escalation beyond whatever this token itself can
# already do). That tradeoff was discussed and accepted explicitly in favor
# of full IaC coverage — see git history for that conversation.
#
# SAFETY PROCEDURE — read before running anything:
#   1. Find this token's ID (NOT the secret value) in the Cloudflare
#      dashboard: My Profile -> API Tokens -> the token used by this root ->
#      the ID is in the URL / token detail page. The ID is not sensitive,
#      safe to share.
#   2. terraform import cloudflare_api_token.infra_root <token_id>
#   3. Run `tofu plan` and READ THE DIFF CAREFULLY before applying anything.
#      The policy list below is reconstructed from this repo's own
#      "Requires:" comments, not read live from the token — if it's missing
#      a permission the token actually has, plan will show that permission
#      being REMOVED. Do not apply if you see any permission_groups removal
#      you don't recognize; tell Claude so the list can be corrected first.
#   4. Only once the diff shows just the intended addition (Turnstile Edit +
#      API Tokens Edit) should you apply.
#
# Some permission-group name strings and the API Tokens permission's
# resource-scope key (user-scoped, not account/zone-scoped) are best-effort
# here — Cloudflare doesn't expose a clean way to verify these without a
# live token. A wrong name/key surfaces as a clear plan/apply-time error
# (an unknown map key or a 400 from the API), never a silent wrong grant —
# if either errors, share the exact message and it'll get fixed.

data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "infra_root" {
  name = "kleinbem-infra" # rename here if the real token has a different name — cosmetic only, doesn't affect import

  # Zone DNS — cloudflare-dns.tf, the tunnel wildcard/root records in main.tf
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["DNS Write"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.main.id}" = "*"
    }
  }

  # Zone WAF (ratelimit ruleset) + Dynamic Redirect (apex->www ruleset) —
  # cloudflare-waf.tf, cloudflare-pages.tf
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.zone["Zone WAF Write"],
      data.cloudflare_api_token_permission_groups.all.zone["Dynamic URL Redirects Write"],
    ]
    resources = {
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.main.id}" = "*"
    }
  }

  # Account-scoped: Tunnel, R2, Pages, Access, Turnstile, Web Analytics
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.account["Cloudflare Tunnel Write"],
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Write"],
      data.cloudflare_api_token_permission_groups.all.account["Pages Write"],
      data.cloudflare_api_token_permission_groups.all.account["Access: Apps and Policies Write"],
      data.cloudflare_api_token_permission_groups.all.account["Turnstile Write"],
      data.cloudflare_api_token_permission_groups.all.account["Account Analytics Read"],
    ]
    resources = {
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    }
  }

  # Self-management — the whole point of this resource. User-scoped (API
  # tokens belong to the account owner, not to a zone/account object), so
  # this policy's resource key is a fixed "com.cloudflare.api.user.*"
  # rather than an account/zone ID substitution — a token only ever acts as
  # its own creating user, so there's no real ID to scope it to. If this
  # specific block errors on apply, that's the part most likely to need a
  # fix — share the exact error message.
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.user["API Tokens Write"],
    ]
    resources = {
      "com.cloudflare.api.user.*" = "*"
    }
  }
}
