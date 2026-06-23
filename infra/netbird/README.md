# NetBird control plane (OpenTofu)

Declarative NetBird **control plane** — groups, access policies, setup keys.
State lives in Cloudflare R2 (`kleinbem-tofu-state`, key `netbird.tfstate`),
mirroring the `github-config` root. Kept out of the local-state bootstrap
`infra/` root because it holds the API token + managed setup keys.

## Boundary
- **NixOS owns the data plane** — peer enrollment via `netbird up`
  (`netbird-autojoin` in `modules/nixos/networking.nix`). Peers self-register;
  this root never manages individual peers.
- **This root owns the control plane** — groups, policies, setup keys, and
  later nameservers / routes / posture checks.

## Prerequisites
1. **NetBird API token** (Personal Access Token, not a setup key) → store in
   `nix-secrets/secrets.yaml` as `netbird_api_token` (`sops updatekeys`).
2. R2 backend env: `CLOUDFLARE_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY` (an R2 access key) — same as `github-config`.
3. Tools: `tofu`, `sops`, `yq` (e.g. `nix shell nixpkgs#opentofu nixpkgs#sops nixpkgs#yq-go`).

## Use
```bash
just plan     # init R2 backend + review changes
just apply    # apply
just schema   # dump provider schema to verify resource/attribute names
```

## Status: SCAFFOLD — schema-verified, not yet applied
- Resource/attribute names reconciled against **`netbirdio/netbird` v0.0.9**
  (`tofu providers schema`). Provider is **unsigned** on the registry (no GPG
  keys) and pre-1.0 — re-verify the schema on any version bump. Not yet applied
  (needs the API token + R2 env); `tofu plan` remains the final check.
- `setup-keys.tf` is **commented out** until you migrate the hand-made console
  key to TF (steps in that file) — avoids orphaning the current
  `netbird_setup_key` that the NixOS autojoin + CI depend on.
- Import existing console objects (the `personal-devices` / `smart-home` groups
  and SSH policy you create by hand now) with `import` blocks so the first apply
  adopts them instead of duplicating.

## Roadmap
1. Token + remote state → `just plan` clean.
2. Import the console-made group/policy; codify the SSH gate here.
3. Flip setup-key ownership to TF (`setup-keys.tf`), fan the value to
   `nix-secrets` (sops) + the `NETBIRD_SETUP_KEY` Actions secret.
4. Scale: groups/policies/posture-checks for the persona fleet (300+).
