# Same passphrase as root infra/, exported as TF_ENCRYPTION by state-env.sh.
# State embeds the API token and setup keys, so R2 only sees ciphertext.
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

      # Plaintext state is rejected, read or write.
      enforced = true
    }
  }
}
