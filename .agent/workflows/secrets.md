---
description: "Manage encrypted secrets with SOPS"
---

# Manage Secrets (SOPS)

Our secrets are stored in the `nix-secrets` repository and encrypted using **sops-nix** with **age** (via YubiKey).

## 1. Prerequisites
- **SOPS**: Installed in your environment.
- **YubiKey**: Plugged in and configured for `age`.

## 2. Edit Secrets
To edit the main secrets file:

```bash
cd nix-secrets
sops secrets.yaml
```

This will decrypt the file into your editor. When you save and close, SOPS will re-encrypt it.

## 3. Adding a New Secret
1. Open the file as shown above.
2. Add a new key:value pair.
3. Save and close.

## 4. Using Secrets in Nix
Secrets are imported into `nix-config`.
- **References**: Usually handled via `config.sops.secrets.<name>.path`.
- **Note**: Ensure the secret is added to the `sops.secrets` attribute set in your NixOS module.

## 5. Troubleshooting
- **No touch prompt?** Check if `gpg-agent` or `pcscd` is running.
- **Permission denied?** Ensure your YubiKey age identity is recognized (`age-plugin-yubikey`).
