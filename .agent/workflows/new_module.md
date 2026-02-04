---
description: "Create a new scalable NixOS or Home Manager module"
---

# Create a New Module

When adding functionality, decide if it belongs in `nix-config` (specific to this system) or `nix-presets` (reusable role).

## 1. Determine Location
*   **System-specific?** -> `nix-config/modules/nixos/<category>/<name>.nix`
*   **Reusable Role?** -> `nix-presets/<category>/<name>.nix`
*   **User-specific?** -> `nix-config/modules/home-manager/<category>/<name>.nix`

## 2. Module Template
Use standard `config, lib, pkgs` arguments.

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.path.to.module;
in
{
  options.path.to.module = {
    enable = lib.mkEnableOption "Description of module";
  };

  config = lib.mkIf cfg.enable {
    # Implementation
    environment.systemPackages = [ pkgs.hello ];
  };
}
```

## 3. Register the Module
Ensure the module is imported in `flake.nix` or a default.nix bundle so it is available to the system.
