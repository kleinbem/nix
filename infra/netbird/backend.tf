# State backend: Cloudflare R2 (s3-compatible), same bucket as root infra/
# (`kleinbem-tofu-state`), key `netbird.tfstate`.
#
# Migrated off interim local state 2026-07-16, once the bucket + scoped R2
# access key + encryption passphrase all existed in sops (root infra/ proved
# the pattern first). Endpoint + credentials can't live here (backend blocks
# take no variables); `just init` generates `.r2-backend.hcl` (gitignored)
# from sops and passes it via `-backend-config`. State is client-side
# encrypted (see encryption.tf) — R2 only ever sees AES-GCM ciphertext.
#
# One-shot migration off local state: `just migrate-state` (the pre-migration
# terraform.tfstate* files stay behind, gitignored, as a fallback copy).
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
