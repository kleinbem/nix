# Token for the r2-budget workflow (tools/r2-budget.sh), which disables the public
# cache's domain past the budget. That needs account-level R2 write (no bucket
# scope exists), so the token lives only in that workflow's secrets.
resource "cloudflare_api_token" "r2_budget" {
  name = "r2-budget-watchdog"

  policies = [{
    resources = jsonencode({
      "com.cloudflare.api.account.${local.account_id}" = "*"
    })
    effect = "allow"
    permission_groups = [{
      id = local.permission_groups.account["Account Analytics Read"]
      }, {
      id = local.permission_groups.account["Workers R2 Storage Write"]
    }]
  }]
}

output "r2_budget_token" {
  description = "Token for kleinbem/nix's r2-budget workflow; synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh."
  sensitive   = true
  value       = cloudflare_api_token.r2_budget.value
}
