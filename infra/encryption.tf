# Client-side state encryption (OpenTofu ≥ 1.7): R2 only ever sees AES-GCM
# ciphertext. tofu state embeds every secret it manages in plaintext (GitHub
# App private key, PATs, NetBird keys, …), so without this the state bucket
# and its access token are secrets-grade surface; with it they hold only
# ciphertext.
#
# The pbkdf2 passphrase is deliberately NOT in this file: tools/tf-apply.sh
# sources it from sops (`tofu_state_passphrase`) and injects it via the
# TF_ENCRYPTION environment merge. Running raw `tofu` without that env fails
# loudly instead of silently writing plaintext — that failure mode is the
# point. Losing the passphrase means re-importing all resources (state is
# unrecoverable), so it lives in sops next to everything else critical.
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

      # MIGRATION WINDOW: fallback lets tofu READ the existing plaintext
      # state; the very next state write comes out encrypted. After the first
      # successful encrypted write, delete the fallback block and flip
      # enforced = true so plaintext state is rejected outright.
      enforced = false
      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
