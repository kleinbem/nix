# S3 credentials for the CI of the projects on the public cache: object
# read/write on the kleinbem-cache bucket only (../public-cache.tf). One token
# for all of them: they share the bucket, so separate tokens wouldn't keep
# them apart. Synced into kleinbem-secrets/infra/terraform.yaml by
# sync-secrets.sh; the main root distributes them (github-secrets.tf).
resource "cloudflare_api_token" "public_cache_ci" {
  name = "kleinbem-cache-ci"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Read"],
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Write"],
    ]
    resources = {
      "com.cloudflare.edge.r2.bucket.${local.account_id}_default_kleinbem-cache" = "*"
    }
  }
}

output "public_cache_ci" {
  description = "S3 credentials for the public cache's CI; synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh."
  sensitive   = true
  value = {
    access_key_id     = cloudflare_api_token.public_cache_ci.id
    secret_access_key = sha256(cloudflare_api_token.public_cache_ci.value)
  }
}
