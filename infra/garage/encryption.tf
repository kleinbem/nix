# Local state, so it must be encrypted at rest: it holds the S3 secret keys
# for restic and the tofu-state bucket. Same scheme as infra/encryption.tf;
# the Justfile injects the pbkdf2 passphrase (sops: tofu_state_passphrase)
# through TF_ENCRYPTION.
terraform {
  encryption {
    key_provider "pbkdf2" "state_key" {
      # passphrase supplied via TF_ENCRYPTION (sops: tofu_state_passphrase)
    }
    method "aes_gcm" "state_enc" {
      keys = key_provider.pbkdf2.state_key
    }
    state {
      method = method.aes_gcm.state_enc

      # Migration completed 2026-10-27 (verified: a wrong passphrase fails
      # with "cipher: message authentication failed").
      # enforced: plaintext state is rejected outright, read or write.
      enforced = true
    }
  }
}
