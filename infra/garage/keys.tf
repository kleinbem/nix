# Access keys (S3 SigV4 credentials) + their bucket permissions. One scoped key
# per consumer — restic only touches `backups`, tofu only touches `tofu-state`.
# Least privilege: no key has `owner`, and neither can read the other's bucket.
resource "garage_key" "restic" {
  name = "restic-key"
}

resource "garage_key" "tofu" {
  name = "tofu-key"
}

resource "garage_bucket_permission" "restic_backups" {
  bucket_id     = garage_bucket.backups.id
  access_key_id = garage_key.restic.id
  read          = true
  write         = true
}

resource "garage_bucket_permission" "tofu_state" {
  bucket_id     = garage_bucket.tofu_state.id
  access_key_id = garage_key.tofu.id
  read          = true
  write         = true
}

# Credentials the consumers need (access key id `.id`, secret `.secret_access_key`
# — both schema-verified against provider v1.0.4). Garage returns the secret only
# at creation, so capture it from `just creds` / `tofu output` right after apply.
output "restic_access_key_id" {
  value = garage_key.restic.id
}
output "restic_secret_key" {
  value     = garage_key.restic.secret_access_key
  sensitive = true
}
output "tofu_access_key_id" {
  value = garage_key.tofu.id
}
output "tofu_secret_key" {
  value     = garage_key.tofu.secret_access_key
  sensitive = true
}
