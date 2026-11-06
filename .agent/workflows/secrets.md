---
description: "Manage encrypted secrets with SOPS"
---

# Manage Secrets (SOPS)

Secrets live in the sibling `kleinbem-secrets` repo (sops + age, YubiKey for Martin's key).
`nix-config` reads them through its `kleinbem-secrets` flake input. Full guide:
`nix-config/docs/SECRETS-MANAGEMENT.md`.

## 1. Prerequisites
- `sops` and `age-plugin-yubikey` (both in the workspace devshell).
- YubiKey plugged in, and its age identity in `~/.config/sops/age/keys.txt` (or a file named by
  `SOPS_AGE_KEY_FILE`); `age-plugin-yubikey --identity` prints it.

## 2. Edit Secrets
From `nix/`:

```bash
cd ../kleinbem-secrets || exit 1
sops nix/shared.yaml               # fleet-wide
sops nix/per-host/<host>.yaml      # one host
```

sops decrypts into your editor and re-encrypts on save. Who can decrypt which path is set in
`kleinbem-secrets/.sops.yaml`.

## 3. Using Secrets in Nix
- Reference the file with `secretFile "<path>"` (`nix-config/lib/secret-file.nix`).
- Declare the key in `sops.secrets` and read it via `config.sops.secrets.<name>.path`.
- Gate the `sops.secrets` entry behind the module's `enable` option.

## 4. Troubleshooting
- **No touch prompt?** Check that `pcscd` is running.
- **Permission denied?** Check that the YubiKey is seen (`age-plugin-yubikey --list`) and that
  its identity is in `~/.config/sops/age/keys.txt` or `SOPS_AGE_KEY_FILE`.
