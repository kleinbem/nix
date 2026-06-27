# State backend.
#
# INTERIM: LOCAL STATE. The R2 (s3) backend below is commented out so this root
# applies with ZERO cloud dependencies — no R2 activation, no access key, no card.
# Only the netbird_api_token in sops is needed. State lives in
# ./terraform.tfstate (gitignored), on the LUKS-encrypted workstation; the import
# blocks in imports.tf make state loss cheap to recover (re-adopt via `just plan`).
#
# MIGRATE TO REMOTE LATER (one command): uncomment the block, init the R2 backend
# (`just init-r2`), then `tofu init -migrate-state` copies the local state up.
# Agreed long-term plan is Garage(local) + R2(offsite); tofu state may instead go
# to a Postgres `pg` backend (drift detection needs CI-reachable state, not S3) —
# decide the target at migration time.
#
# terraform {
#   backend "s3" {
#     bucket = "kleinbem-tofu-state"
#     key    = "netbird.tfstate"
#     region = "auto"
#
#     # R2 is S3-compatible but not AWS — skip the AWS-specific probes.
#     skip_credentials_validation = true
#     skip_region_validation      = true
#     skip_requesting_account_id  = true
#     skip_metadata_api_check     = true
#     skip_s3_checksum            = true
#     use_path_style              = true
#     use_lockfile                = true # native state locking via R2 conditional writes
#   }
# }
