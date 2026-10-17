# Local state, so it must be encrypted at rest: it holds the S3 secret keys
# for restic and the tofu-state bucket. Same scheme as infra/encryption.tf;
# the Justfile injects the pbkdf2 passphrase (sops: tofu_state_passphrase)
# through TF_ENCRYPTION.
#
# MIGRATION: the fallback lets the first `just apply` read the old plaintext
# state and write it back encrypted. After that run, delete the plaintext
# terraform.tfstate.backup, drop the fallback block and set enforced = true.
terraform {
  encryption {
    key_provider "pbkdf2" "state_key" {
      # passphrase supplied via TF_ENCRYPTION (sops: tofu_state_passphrase)
    }
    method "aes_gcm" "state_enc" {
      keys = key_provider.pbkdf2.state_key
    }
    method "unencrypted" "migrate" {}
    state {
      method = method.aes_gcm.state_enc
      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
