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
# First-apply adoption (do once, so tofu adopts the hand-made console objects):
cp imports.auto.tfvars.example imports.auto.tfvars
just ids > imports.auto.tfvars   # writes the live group/policy ids as tfvars

just plan     # init R2 backend + review changes — expect "N to import, 0 to add"
just apply    # apply once the plan is clean

# Close the cosmetic gate (only after the explicit SSH policy is adopted):
just list-policies                 # find the built-in "All -> All" default
just close-default-policy <id>     # delete it (confirmed; reversible in console)

just schema   # dump provider schema to verify resource/attribute names
```

If `just plan` shows anything **to add** for the groups/policy, an id in
`imports.auto.tfvars` is wrong or empty and tofu would DUPLICATE the object —
fix the tfvars before applying.

## Status: SCAFFOLD — schema-verified + import-ready, not yet applied
- Resource/attribute names reconciled against **`netbirdio/netbird` v0.0.9**
  (`tofu providers schema`). Provider is **unsigned** on the registry (no GPG
  keys) and pre-1.0 — re-verify the schema on any version bump. Not yet applied
  (needs the API token + R2 env); `tofu plan` remains the final check.
- `setup-keys.tf` is **commented out** until you migrate the hand-made console
  key to TF (steps in that file) — avoids orphaning the current
  `netbird_setup_key` that the NixOS autojoin + CI depend on.
- `imports.tf` + `just ids` adopt the hand-made console objects
  (`personal-devices` / `smart-home` groups, `ssh-personal-to-smart-home`
  policy) on the first apply instead of duplicating them. Empty id = create
  fresh.
- The built-in **"All -> All" default policy** is closed via
  `just close-default-policy` (API, confirmed, reversible), not as a managed
  resource — see the rationale + promote-to-declarative sketch in `policies.tf`.

## Roadmap
1. Token + remote state → `just plan` clean (import blocks adopt, 0 to add).
2. Close the default All→All policy; the explicit SSH policy becomes the gate.
3. Flip setup-key ownership to TF (`setup-keys.tf`), fan the value to
   `nix-secrets` (sops) + the `NETBIRD_SETUP_KEY` Actions secret.
4. Promote the default-policy closure to a managed `netbird_policy` resource
   once the live schema is confirmed (`just schema`).
5. Scale: groups/policies/posture-checks for the persona fleet (300+).
