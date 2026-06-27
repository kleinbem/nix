# Garage control plane (OpenTofu)

Declarative Garage **S3 control plane** — buckets, access keys, and key→bucket
permissions — via the community `jkossis/garage` provider against the Garage
Admin API (v2). Mirrors `infra/netbird`: NixOS owns the daemon, this root owns
the control plane.

## Boundary
- **NixOS owns the daemon + node config** — `services.garage` in
  `nix-config/hosts/nixos-nvme/garage.nix`, and the one-time cluster **layout**
  (`garage layout assign/apply`, a node-lifecycle CLI step).
- **This root owns the S3 control plane** — buckets, keys, permissions. Buckets
  and keys become code instead of `garage bucket create` / `garage key create`.

## Prerequisites
1. **Garage running with a layout applied** (objects can't be stored otherwise):
   ```bash
   sudo garage layout assign -z dc1 -c 1T "$(sudo garage node id -q | cut -d@ -f1)"
   sudo garage layout apply --version 1
   ```
2. **Admin token in sops** — `nix-secrets/secrets.yaml` → `garage_admin_token`
   (the same GARAGE_ADMIN_TOKEN the service uses). Already present.
3. Run on the host that runs garage (admin API is on loopback `:3903`), or set
   `TF_VAR_garage_endpoint` to reach it over NetBird. Tools: `tofu`, `sops`, `yq`.

## Use
```bash
just plan      # review buckets/keys/permissions
just apply     # create them
just creds     # print access key id + secret for restic / tofu (capture these!)
just schema    # verify provider resource/attribute names
```

## Status: SCAFFOLD — schema-verified, not yet applied
- `jkossis/garage` **v1.0.4** (community), pinned in `main.tf`. NOT on the
  OpenTofu registry → source is fully qualified to the Terraform registry.
  Bucket/key/permission attributes verified against v1.0.4 via `just schema`;
  re-verify on upgrades.
- **Local state** by design — this root creates the `tofu-state` bucket, so it
  can't store its own state in it (see `backend.tf`).
- After applying, other roots (e.g. `infra/netbird`) can migrate their state into
  the `tofu-state` bucket via the s3 backend over NetBird.

## Manages
- Buckets: `backups` (restic), `tofu-state` (remote state for other roots)
- Keys: `restic-key` (RW on backups), `tofu-key` (RW on tofu-state) — least
  privilege, no cross-bucket access, no `owner`.
