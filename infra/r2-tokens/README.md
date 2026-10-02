# Per-host R2 backup tokens (OpenTofu)

One bucket-scoped R2 token per fleet host for the backup engine's `r2`
destination. Hosts come from `../backup-hosts.json` (`nix-config#backupHosts`:
every host that registers `my.backup.items`); each host's rclone config is
written to `kleinbem-secrets/nix/per-host/<host>.yaml` as
`backup_r2_rclone_config`.

Separate root on purpose: it holds the only token-minting credential
(`cloudflare_token_minter_token`, API Tokens: Edit = effectively account
admin), so the main `infra/` root never sees it and it's only decrypted
when the host list changes.

## One-time bootstrap
1. Cloudflare dashboard → My Profile → API Tokens → Create Custom Token:
   permission **User → API Tokens → Edit** only; restrict *Client IP Address
   Filtering* to where you run tofu.
2. `sops kleinbem-secrets/infra/terraform.yaml` → `cloudflare_token_minter_token: <token>`.

## Use
```bash
nix shell nixpkgs#opentofu nixpkgs#sops nixpkgs#yq-go nixpkgs#jq
just apply    # plan + confirm + sync configs into kleinbem-secrets
```
Then push kleinbem-secrets; nix-config picks it up with its next lock bump.

Revoke a host: remove its backup items (or the host) in nix-config, `just apply`.
Fails closed: without the minter token nothing runs — it never plans to
destroy the existing tokens.
