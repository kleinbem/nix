# Client-side state encryption: state holds every managed secret in
# plaintext, so R2 only ever gets AES-GCM ciphertext.
#
# tools/tf-apply.sh injects the passphrase from sops (`tofu_state_passphrase`)
# via TF_ENCRYPTION; raw `tofu` without it fails instead of writing
# plaintext. Losing the passphrase means re-importing every resource.
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
