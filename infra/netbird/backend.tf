# Same R2 bucket as root infra/. Backend blocks take no variables, so
# state-env.sh writes endpoint + credentials into `.r2-backend.hcl`
# (gitignored), passed via `-backend-config`.
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
