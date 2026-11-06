locals {
  # nix-config#backupHosts → ../backup-hosts.json (tools/gen-iac-data.sh):
  # every fleet host that registers my.backup.items.
  backup_hosts = toset(jsondecode(file("${path.module}/../backup-hosts.json")))
  # nonsensitive: object keys / URLs can't carry a sensitive mark, and the
  # account id isn't secret anyway (it's in every R2 endpoint URL).
  account_id = nonsensitive(var.cloudflare_account_id)

  # v5 policies take permission-group IDs, not names. Same name → id maps per
  # scope as v4's data source had (r2, zone, account).
  permission_group_scopes = {
    r2      = "com.cloudflare.edge.r2.bucket"
    zone    = "com.cloudflare.api.account.zone"
    account = "com.cloudflare.api.account"
  }
  permission_groups = {
    for k, scope in local.permission_group_scopes : k => {
      for g in data.cloudflare_api_token_permission_groups_list.all.result :
      g.name => g.id if contains(g.scopes, scope)
    }
  }
}

data "cloudflare_api_token_permission_groups_list" "all" {
  max_items = 1000
}

resource "cloudflare_api_token" "backup_r2" {
  for_each = local.backup_hosts
  name     = "backup-r2-${each.key}"

  # Object read/write on the backup bucket only: no bucket admin, no other
  # buckets. Deletes are possible (restic prune needs them); the bucket lock
  # on secure/ (infra/cloudflare-r2.tf) protects recent secure bundles.
  policies = [{
    resources = jsonencode({
      "com.cloudflare.edge.r2.bucket.${local.account_id}_default_${var.backup_bucket}" = "*"
    })
    effect = "allow"
    permission_groups = [{
      id = local.permission_groups.r2["Workers R2 Storage Bucket Item Read"]
      }, {
      id = local.permission_groups.r2["Workers R2 Storage Bucket Item Write"]
    }]
  }]
}

# R2's S3 credentials derive from the API token: Access Key ID = token id,
# Secret Access Key = SHA-256 (hex) of the token value.
output "backup_r2_rclone_configs" {
  description = "host → rclone config defining the `r2` remote; synced into kleinbem-secrets by sync-secrets.sh."
  sensitive   = true
  value = {
    for host, t in cloudflare_api_token.backup_r2 : host => <<-EOT
      [r2]
      type = s3
      provider = Cloudflare
      access_key_id = ${t.id}
      secret_access_key = ${sha256(t.value)}
      endpoint = https://${local.account_id}.r2.cloudflarestorage.com
      region = auto
      acl = private
      no_check_bucket = true
    EOT
  }
}
