# State encryption, same passphrase as infra/ (TF_ENCRYPTION from state-env.sh).
# Enforced because this state holds live token values: R2 only sees ciphertext,
# and raw `tofu` without the env fails instead of writing plaintext.
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
