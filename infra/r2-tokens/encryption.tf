# Client-side state encryption — same pattern and passphrase as root infra/
# and netbird/ (sops: tofu_state_passphrase, injected via TF_ENCRYPTION by
# state-env.sh). Enforced from the first apply: this state holds live R2
# token values, so R2 must only ever see ciphertext, and raw `tofu` without
# the env fails loudly instead of writing plaintext.
terraform {
  encryption {
    key_provider "pbkdf2" "state_key" {
      # passphrase supplied via TF_ENCRYPTION (sops: tofu_state_passphrase)
    }

    method "aes_gcm" "state_enc" {
      keys = key_provider.pbkdf2.state_key
    }

    state {
      method   = method.aes_gcm.state_enc
      enforced = true
    }
  }
}
