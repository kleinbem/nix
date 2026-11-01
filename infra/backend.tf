# State lives in R2 bucket `kleinbem-tofu-state`, which this root also manages
# (main.tf, prevent_destroy). Backend blocks take no variables, so
# tools/tf-apply.sh writes endpoint + R2 keys into a -backend-config file;
# not AWS_* env vars, which the aws provider would take as real AWS creds.
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
