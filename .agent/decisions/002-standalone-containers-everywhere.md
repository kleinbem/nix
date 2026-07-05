# ADR 002: Standalone containers everywhere (manifest-based updates)

- **Status**: accepted
- **Date**: 2026-07-06
- **Deciders**: martin (+ Claude session diagnosing the two-model split)

## Context

nspawn containers had two update models depending on which host they sat on:

- **Standalone** (nixos-nvme only): container closure registered as its own
  Nix profile (`/nix/var/nix/profiles/containers/<name>`), nspawn boots from
  the `/var/lib/machines/<name>/current` symlink, refreshed by the nightly
  `update-containers` timer (03:00). Decoupled from host generations.
- **Embedded** (core-pi, hass-pi, orin): container closure baked into the
  host's system closure, updated only when the host generation flips
  (nightly `system.autoUpgrade` at 04:00 from the `production` tag).

Containers migrate between devices, so their update semantics silently
changed with placement (timing, restart granularity, rollback coupling).
The standalone stage step also ran `nix build github:…#container-factory…`
**on the device** — a full flake eval, unaffordable on RPi5-class hosts,
which is why the Pis had stayed embedded.

## Decision

1. **Standalone is the only model.** Every deployed container on every host
   goes through the updater; embedded remains only as a per-host, explicit
   exclusion (e.g. `caddy` on nixos-nvme, excluded so the reverse proxy is
   not auto-restarted).
2. **Updates are eval-free on devices.** CI publishes a manifest
   (`rev`, `systems.<system>.<container> → store path`) as a rolling GitHub
   release asset (`container-manifest`); the updater fetches it, filters by
   its own `stdenv.hostPlatform.system`, and `nix-store --realise`s the path
   from Attic. No flake eval leaves CI.
3. **Both architectures build in CI — deployment-driven.** `container-factory`
   (x86_64) gains an aarch64 twin (`container-factory-aarch64`, same catalogue
   minus x86-only entries like llama-cpp). build-all builds both factory
   toplevels (one build materializes every container closure) and pushes to
   Attic. **Amendment (same day):** factories enable exactly the union of
   containers registered with `my.services.container-updater` on real hosts of
   the matching arch (computed in `modules/flake/hosts.nix`, passed as the
   `deployedContainers` specialArg), plus a per-arch `preWarm` list for
   deliberate pre-caching. This cut CI from ~57 container closures to the 13
   deployed, and manifest completeness holds by construction: a device can
   only request containers it enables, and enabling one puts it in the
   factory set. The updater additionally intersects its registration list
   with `config.containers`, so OCI/podman services (comfyui, vllm, langflow
   — no nspawn closure) can never enter the stage pipeline.
4. **Manifest is gated like hosts.** promote-production generates the
   manifest for the exact promoted SHA and drops any container whose full
   closure is not substitutable (same `nix build --dry-run` gate as host
   closures) — devices then keep the previous closure rather than compile.
5. **Changed-only activation.** Stage records whether the profile target
   moved; the bulk updater restarts only changed (or not-running)
   containers. home-assistant no longer blips nightly without an update.
6. **Boot-time bootstrap.** Standalone `container@` units carry
   `ConditionPathExists` on the symlink, so a freshly-flipped host would
   leave containers down until 03:00. `container-updater-bootstrap`
   (multi-user.target) stages any container with no symlink immediately.

## Consequences

- Moving a container between hosts no longer changes its update behavior.
- Pi host closures shrink (containers leave them); host autoUpgrade and
  container updates are fully independent everywhere.
- Host generation rollback no longer rolls containers back anywhere —
  container rollback = `nix-env --profile …/containers/<name> --rollback`
  plus restart (uniform, but different from the old embedded semantics).
- Transition risk: the first production pull after the flip needs the
  manifest to already exist for aarch64. Factory builds are best-effort in
  build-all, so a failed first arm factory build would leave Pi containers
  down until the next green cycle (bootstrap + nightly timer self-heal).
  Accepted because the arm closures are already largely cached from the
  previously-embedded host builds.
- Follow-ups: harden factory builds from best-effort to blocking once green
  for a full cycle; consider asserting manifest coverage for each deployed
  host's updater list in verify-cache (blocking) at the same time.
