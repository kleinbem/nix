---
description: "Deploy and verify configuration on a remote host"
---

# Deploy Remote Host

Hosts pull CI-validated commits on their own. Use this only for an immediate deploy to one
remote host (like orin-nano or core-pi). Commands run from `nix/`.

## 1. Verify Connectivity
```bash
ping -c1 -W2 <HOST_NAME>
```
Stop if the host doesn't answer.

## 2. Apply Configuration
```bash
just apply <HOST_NAME>
```
This runs `just dev::apply <HOST_NAME>` in `nix-config`; `just apply --help` lists the flags.

## 3. Post-Deployment Health Check
```bash
ssh <HOST_NAME> systemctl list-units --failed --no-legend
```
Any output is a failed unit: look at it (`ssh <HOST_NAME> journalctl -u <unit> -n 50`)
before calling the host done.
