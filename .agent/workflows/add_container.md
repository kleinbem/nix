---
description: "How to add a new container preset"
---

# Add a Container Preset

When adding a new NixOS container (e.g., via `mkContainer`), follow these steps:

1. Create your container file under `nix-presets/containers/<name>.nix` (or an appropriate sub-flake).
2. Look at `nix-presets/AGENTS.md` for specific conventions.
3. **Key gotcha:** You must register the new file in `nix-presets/flake.nix` under `nixosModules`.
   * If you skip this, hosts will not be able to import it via `inputs.nix-presets.nixosModules.<name>`.
4. Ensure the container has an `enable = false` default to respect the Switchboard pattern.
