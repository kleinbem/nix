# State backend: Cloudflare R2 (s3-compatible), bucket `kleinbem-tofu-state`.
#
# The bucket is created by THIS root (main.tf: cloudflare_r2_bucket.tofu_state)
# — that was a chicken-and-egg only for the FIRST apply, which ran on local
# state. The bucket exists now, so this root's own state lives in it too
# (guarded by prevent_destroy on the bucket resource).
#
# The endpoint and the R2 access key can't be expressed here (backend blocks
# take no variables); tools/tf-apply.sh generates `.r2-backend.hcl` (gitignored)
# from sops (`r2_state_access_key_id` / `r2_state_secret_access_key` +
# `cloudflare_account_id`) and passes it via `tofu init -backend-config=…`.
# Credentials deliberately go in that file, NOT AWS_* env vars — the aws
# provider (aws-ses.tf) reads ambient env for real-AWS auth and must not pick
# up R2 keys.
#
# One-shot migration off local state: `./tools/tf-apply.sh --migrate-state`
# (the pre-migration terraform.tfstate* files stay behind, gitignored, as a
# fallback copy).
terraform {
  backend "s3" {
    bucket = "kleinbem-tofu-state"
    key    = "infra.tfstate"
    region = "auto"

    # R2 is S3-compatible but not AWS — skip the AWS-specific probes.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = true # native state locking via R2 conditional writes
  }
}
