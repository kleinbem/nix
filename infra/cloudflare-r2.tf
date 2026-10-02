# ---------------------------------------------------------------------------
# R2 bucket for off-site fleet backups — the `r2` destination of
# nix-presets' backup-engine, wired fleet-wide in
# nix-config/modules/nixos/backup.nix. Layout:
#   secure/<host>/<host>-<ts>.tar.gz.age   age-encrypted secure-tier bundles
#   restic/<host>                          restic repo per host (bulk tier)
#
# Only the bucket is managed here. The per-host S3 credentials (one token per
# host, so one host's access can be revoked alone) live in their own root,
# infra/r2-tokens/ — minting tokens needs "API Tokens: Edit", which this
# root's cloudflare_api_token deliberately doesn't hold. That root writes each
# host's `backup_r2_rclone_config` into kleinbem-secrets/nix/per-host/<host>.yaml.
#
# Tamper-proofing: R2 tokens can't be scoped write-without-delete, so the
# `secure/` prefix gets a bucket LOCK rule instead — objects there can't be
# deleted or overwritten for 30d, even with the uploading host's own token.
# `restic/` is deliberately NOT locked: restic prune has to delete packs.
# Lifecycle expires secure bundles after 365d.
#
# Requires: cloudflare_api_token with "Workers R2 Storage: Edit" (same perm the
# tofu_state bucket in main.tf already needs).
# ---------------------------------------------------------------------------

resource "cloudflare_r2_bucket" "backup" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-backup"

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Lock + lifecycle rules. The pinned cloudflare provider (~> 4.0) has no
# resources for these (cloudflare_r2_bucket_lock / _lifecycle are v5-only),
# so they're applied via the API from terraform_data. PUT replaces the whole
# rule set, so this is idempotent and the JSON below IS the full desired
# state; re-runs whenever it changes. Replace with the native v5 resources as
# part of the provider v5 migration.
# ---------------------------------------------------------------------------

locals {
  backup_bucket_lock = {
    rules = [{
      id        = "secure-30d"
      enabled   = true
      prefix    = "secure/"
      condition = { type = "Age", maxAgeSeconds = 30 * 86400 }
    }]
  }

  backup_bucket_lifecycle = {
    rules = [
      {
        # Mirrors the default rule R2 gives every new bucket (PUT replaces it).
        id                              = "abort-multipart-7d"
        enabled                         = true
        conditions                      = { prefix = "" }
        abortMultipartUploadsTransition = { condition = { type = "Age", maxAge = 7 * 86400 } }
      },
      {
        id                      = "secure-expire-365d"
        enabled                 = true
        conditions              = { prefix = "secure/" }
        deleteObjectsTransition = { condition = { type = "Age", maxAge = 365 * 86400 } }
      },
    ]
  }
}

resource "terraform_data" "backup_bucket_rules" {
  triggers_replace = {
    bucket    = cloudflare_r2_bucket.backup.name
    lock      = jsonencode(local.backup_bucket_lock)
    lifecycle = jsonencode(local.backup_bucket_lifecycle)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    environment = {
      CF_API_TOKEN  = var.cloudflare_api_token
      CF_ACCOUNT_ID = var.cloudflare_account_id
      BUCKET        = cloudflare_r2_bucket.backup.name
      LOCK_JSON     = jsonencode(local.backup_bucket_lock)
      LIFECYCLE     = jsonencode(local.backup_bucket_lifecycle)
    }
    command = <<-EOT
      put() {
        curl -fsS -X PUT \
          -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
          "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets/$BUCKET/$1" \
          --data "$2" | jq -e '.success' >/dev/null
      }
      put lock "$LOCK_JSON"
      put lifecycle "$LIFECYCLE"
      echo "kleinbem-backup: lock + lifecycle rules applied"
    EOT
  }
}
