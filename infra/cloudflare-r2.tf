# ---------------------------------------------------------------------------
# R2 bucket for off-site fleet backups (core-pi → restic + age-encrypted vault
# dumps). Paired with nix-config/hosts/core-pi/backup.nix.
#
# Only the bucket is Terraform-managed. The S3 access key pair is NOT: create
# it once in the dashboard (R2 → "Manage R2 API Tokens" → Create API token →
# permission "Object Read & Write", scope to this bucket) — that screen shows
# the Access Key ID, Secret Access Key and the S3 endpoint directly, which go
# straight into `backup_rclone_config` in kleinbem-secrets. Automating token
# creation needs the root cloudflare_api_token to also hold "API Tokens: Edit",
# which it deliberately doesn't.
#
# Hardening follow-ups (not blockers): enable Object Lock (30d) on the bucket,
# and/or scope the token to write-only, so a core-pi compromise can't delete
# history. For now: date-stamped objects + the freshness watchdog in backup.nix.
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
