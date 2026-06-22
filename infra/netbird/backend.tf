# Remote state in Cloudflare R2 (S3-compatible), separate key from github-config.
# This root holds the NetBird API token + managed setup keys in state, so it must
# NOT use the local-state bootstrap root (infra/) — encryption-at-rest + locking
# matter here. Bucket `kleinbem-tofu-state` is provisioned by infra/main.tf.
#
# Supplied at init time (NOT committed):
#   - endpoint -> -backend-config (generated from $CLOUDFLARE_ACCOUNT_ID; see Justfile)
#   - creds    -> AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env (an R2 access key)
terraform {
  backend "s3" {
    bucket = "kleinbem-tofu-state"
    key    = "netbird.tfstate"
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
