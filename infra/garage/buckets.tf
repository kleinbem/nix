# S3 buckets. `global_alias` is the bucket's S3 name; clients address it by this
# alias (path- or vhost-style via s3.kleinbem.dev). First two consumers:
#   backups    — restic target (immutable tier lives on the R2 offsite, not here)
#   tofu-state — remote state for OTHER roots (NOT this one — chicken-and-egg)
resource "garage_bucket" "backups" {
  global_alias = "backups"
}

resource "garage_bucket" "tofu_state" {
  global_alias = "tofu-state"
}

# Ente museum's object store (core-pi), replacing the in-container MinIO.
resource "garage_bucket" "ente" {
  global_alias = "ente"
}
