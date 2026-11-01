# ---------------------------------------------------------------------------
# Off-site fleet backups (backup-engine `r2` destination): secure/<host>/ holds
# age bundles, restic/<host> a restic repo. Per-host tokens live in
# infra/r2-tokens/, since minting them needs "API Tokens: Edit", which this
# root's token doesn't hold.
# R2 tokens can't be write-without-delete, so secure/ gets a 30d bucket lock
# instead. restic/ stays unlocked because prune must delete packs.
# ---------------------------------------------------------------------------

resource "cloudflare_r2_bucket" "backup" {
  account_id = var.cloudflare_account_id
  name       = "kleinbem-backup"

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Provider v4 has no lock/lifecycle resources (v5 only), so these go through
# the API. PUT replaces the whole rule set, so the JSON below is the full state.
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
