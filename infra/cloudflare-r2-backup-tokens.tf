# Per-host R2 credentials for the backup engine's `r2` destination
# (nix-config/modules/nixos/backup.nix → backup_r2_rclone_config in
# kleinbem-secrets/nix/per-host/<host>.yaml). One token per host so a single
# host's access can be revoked alone: drop it from the list and apply.
#
# Hosts come from backup-hosts.json (nix-config#backupHosts via
# tools/gen-iac-data.sh): every fleet host that registers my.backup.items.
# tf-apply.sh writes each host's rclone config into its sops file after apply.
#
# Minting API tokens needs "API Tokens: Edit", which makes a credential
# effectively account-admin (it can mint a token with any permission). So it
# is NOT on cloudflare_api_token: a separate, bootstrap-once token holding only
# that permission is used through the `minter` alias below, for these
# resources only. Manual bootstrap (once): Cloudflare dashboard → My Profile →
# API Tokens → Create Custom Token → permission User / API Tokens / Edit →
# `sops kleinbem-secrets/infra/terraform.yaml` → cloudflare_token_minter_token.
# Empty (pre-bootstrap) = this file manages nothing.
#
# R2's S3 credentials are derived from the API token: Access Key ID = token
# id, Secret Access Key = SHA-256 (hex) of the token value.
# ---------------------------------------------------------------------------

variable "cloudflare_token_minter_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Cloudflare API token with ONLY User → API Tokens: Edit. Mints the per-host R2 backup tokens below; nothing else uses it. Bootstrapped once by hand (see this file's header)."
}

provider "cloudflare" {
  alias     = "minter"
  api_token = var.cloudflare_token_minter_token
}

locals {
  # nonsensitive() on the *boolean* only ("is a minter configured").
  r2_backup_hosts = nonsensitive(var.cloudflare_token_minter_token == "") ? toset([]) : toset(
    jsondecode(file("${path.module}/backup-hosts.json"))
  )
  r2_backup_endpoint = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
}

data "cloudflare_api_token_permission_groups" "minter" {
  count    = length(local.r2_backup_hosts) > 0 ? 1 : 0
  provider = cloudflare.minter
}

resource "cloudflare_api_token" "backup_r2" {
  for_each = local.r2_backup_hosts
  provider = cloudflare.minter
  name     = "backup-r2-${each.key}"

  # Object read/write on the backup bucket only — no bucket admin, no other
  # buckets. Deletes are possible (restic prune needs them); the bucket lock
  # on secure/ (cloudflare-r2.tf) is what protects recent secure bundles.
  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.minter[0].r2["Workers R2 Storage Bucket Item Read"],
      data.cloudflare_api_token_permission_groups.minter[0].r2["Workers R2 Storage Bucket Item Write"],
    ]
    resources = {
      # nonsensitive: an object key can't be sensitive, and the account id
      # isn't secret anyway (it's in every R2 endpoint URL).
      "com.cloudflare.edge.r2.bucket.${nonsensitive(var.cloudflare_account_id)}_default_${cloudflare_r2_bucket.backup.name}" = "*"
    }
  }
}

output "backup_r2_rclone_configs" {
  description = "host → rclone config defining the `r2` remote. Written to kleinbem-secrets/nix/per-host/<host>.yaml (backup_r2_rclone_config) by tools/tf-apply.sh."
  sensitive   = true
  value = {
    for host, t in cloudflare_api_token.backup_r2 : host => <<-EOT
      [r2]
      type = s3
      provider = Cloudflare
      access_key_id = ${t.id}
      secret_access_key = ${sha256(t.value)}
      endpoint = ${local.r2_backup_endpoint}
      region = auto
      acl = private
      no_check_bucket = true
    EOT
  }
}
