# Client-side state encryption — same pattern and passphrase as root infra/
# (sops: tofu_state_passphrase, injected via the TF_ENCRYPTION env merge by the
# Justfile). netbird state embeds the API token and setup keys in plaintext,
# so R2 must only ever see ciphertext. Raw `tofu` without the env fails loudly
# instead of silently writing plaintext — deliberate.
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

      # Migration completed 2026-07-16 (verified: dummy passphrase fails with
      # "cipher: message authentication failed" — the R2 object is ciphertext).
      # enforced: plaintext state is rejected outright, read or write.
      enforced = true
    }
  }
}
