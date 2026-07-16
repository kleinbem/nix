# Client-side state encryption — same pattern and passphrase as root infra/
# (sops: tofu_state_passphrase, injected via the TF_ENCRYPTION env merge by the
# Justfile). netbird state embeds the API token and setup keys in plaintext,
# so R2 must only ever see ciphertext. Raw `tofu` without the env fails loudly
# instead of silently writing plaintext — deliberate.
#
# enforced=false + fallback stay until the FIRST encrypted write lands (the
# `just migrate-state` run migrates plaintext local state up, and the next
# apply encrypts). After verifying ciphertext (a dummy passphrase must fail
# with "message authentication failed"), delete the fallback and set
# enforced = true — same closure step root infra/ went through.
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

      enforced = false
      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
