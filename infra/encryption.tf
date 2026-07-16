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

    state {
      method = method.aes_gcm.state_enc

      # Migration completed 2026-07-16 (verified: dummy passphrase fails with
      # "cipher: message authentication failed" — the R2 object is ciphertext).
      # enforced: plaintext state is rejected outright, read or write.
      enforced = true
    }
  }
}
