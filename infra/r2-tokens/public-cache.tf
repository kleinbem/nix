# Object read/write on kleinbem-cache only, for the CI of public-cache projects.
# One shared token: they share the bucket anyway. sync-secrets.sh copies it to
# kleinbem-secrets infra/terraform.yaml; github-secrets.tf distributes it.
resource "cloudflare_api_token" "public_cache_ci" {
  name = "kleinbem-cache-ci"

  policies = [{
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.account_id}_default_kleinbem-cache" = "*"
    })
    effect = "allow"
    permission_groups = [{
      id = local.permission_groups.r2["Workers R2 Storage Bucket Item Read"]
      }, {
      id = local.permission_groups.r2["Workers R2 Storage Bucket Item Write"]
    }]
  }]
}

output "public_cache_ci" {
  description = "S3 credentials for the public cache's CI; synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh."
  sensitive   = true
  value = {
    access_key_id     = cloudflare_api_token.public_cache_ci.id
    secret_access_key = sha256(cloudflare_api_token.public_cache_ci.value)
  }
}
