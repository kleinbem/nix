# kleinbem/nix's r2-budget workflow (tools/r2-budget.sh): reads the account's
# R2 usage and, past the budget, disables the custom domain of the public
# cache (cache.kleinbem.dev). Disabling the domain needs account-level R2 write (no bucket
# scope exists for bucket settings), so this token lives only in that
# workflow's secrets, which scheduled runs on main see and fork PRs don't.
# Synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh.
resource "cloudflare_api_token" "r2_budget" {
  name = "r2-budget-watchdog"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.account["Account Analytics Read"],
      data.cloudflare_api_token_permission_groups.all.account["Workers R2 Storage Write"],
    ]
    resources = {
      "com.cloudflare.api.account.${local.account_id}" = "*"
    }
  }
}

output "r2_budget_token" {
  description = "Token for kleinbem/nix's r2-budget workflow; synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh."
  sensitive   = true
  value       = cloudflare_api_token.r2_budget.value
}
