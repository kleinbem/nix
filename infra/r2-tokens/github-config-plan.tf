# Read-only on kleinbem-tofu-state, for github-config's PR/drift plan, which
# runs from any branch. It can't write state or the lock, so that plan runs with
# -lock=false. The other roots in the bucket encrypt their state.
# sync-secrets.sh copies it to infra/terraform.yaml; github-secrets.tf
# distributes it as PLAN_R2_*.
resource "cloudflare_api_token" "github_config_plan" {
  name = "github-config-plan"

  policies = [{
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.account_id}_default_kleinbem-tofu-state" = "*"
    })
    effect = "allow"
    permission_groups = [{
      id = "Workers R2 Storage Bucket Item Read"
    }]
  }]
}

output "github_config_plan_r2" {
  description = "Read-only S3 credentials for github-config's plan; synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh."
  sensitive   = true
  value = {
    access_key_id     = cloudflare_api_token.github_config_plan.id
    secret_access_key = sha256(cloudflare_api_token.github_config_plan.value)
  }
}
