# State backend: Cloudflare R2, same bucket as root infra/ and netbird/
# (`kleinbem-tofu-state`), key `r2-tokens.tfstate`. Endpoint + credentials come
# from sops via state-env.sh (`.r2-backend.hcl`, gitignored) — backend blocks
# take no variables. State is client-side encrypted (encryption.tf): it holds
# every host's R2 token value.
terraform {
  backend "s3" {
    bucket = "kleinbem-tofu-state"
    key    = "r2-tokens.tfstate"
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
