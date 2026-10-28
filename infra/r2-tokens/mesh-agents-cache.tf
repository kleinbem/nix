# S3 credentials for kleinbem/mesh-agents' CI: object read/write on the public
# mesh-agents-cache bucket only (../mesh-agents-cache.tf). Synced into
# kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh; the main root
# distributes them as mesh-agents' Actions secrets (github-secrets.tf).
resource "cloudflare_api_token" "mesh_agents_cache_ci" {
  name = "mesh-agents-cache-ci"

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Read"],
      data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Write"],
    ]
    resources = {
      "com.cloudflare.edge.r2.bucket.${local.account_id}_default_mesh-agents-cache" = "*"
    }
  }
}

output "mesh_agents_cache_ci" {
  description = "S3 credentials for mesh-agents' CI; synced into kleinbem-secrets/infra/terraform.yaml by sync-secrets.sh."
  sensitive   = true
  value = {
    access_key_id     = cloudflare_api_token.mesh_agents_cache_ci.id
    secret_access_key = sha256(cloudflare_api_token.mesh_agents_cache_ci.value)
  }
}
