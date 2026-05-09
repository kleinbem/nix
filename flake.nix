{
  description = "Meta-Workspace for Nix Repositories";

  inputs = {
    # Tracking nixos-unstable to pull in latest upstream fixes for COSMIC:
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv = {
      # FIXME: Temporary pin to bypass broken libghostty-vt requirement in devenv 2.1 (released May 7, 2026)
      url = "github:cachix/devenv/070577452d0c81d62168ef8b158ee4317ace7e21";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.ghostty.follows = "ghostty";
    };
    ghostty.url = "github:mitchellh/ghostty";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # colmena flake removed — using nixpkgs for deployment definitions and tool

    nix-secrets = {
      url = "github:kleinbem/nix-secrets";
      flake = false;
    };

    # Import Local Devshell to keep tools consistent
    nix-devshells = {
      url = "github:kleinbem/nix-devshells";
      inputs = {
        devenv.follows = "devenv";
        nixpkgs.follows = "nixpkgs";
        nixos-generators.follows = "nixos-generators";
      };
    };

    # Import NixOS Config to expose systems at root
    nix-config = {
      url = "github:kleinbem/nix-config";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-master.follows = "nixpkgs-master";
        nix-devshells.follows = "nix-devshells";
        nix-hardware.follows = "nix-hardware";
        nix-presets.follows = "nix-presets";
        nix-packages.follows = "nix-packages";
        nix-templates.follows = "nix-templates";
        sops-nix.follows = "sops-nix";
        home-manager.follows = "home-manager";
        nix-secrets.follows = "nix-secrets";
      };
    };

    nix-presets = {
      url = "github:kleinbem/nix-presets";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
        nix-packages.follows = "nix-packages";
      };
    };

    nix-hardware = {
      url = "github:kleinbem/nix-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.jetpack-nixos.follows = "jetpack-nixos";
    };

    nix-packages = {
      url = "github:kleinbem/nix-packages";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
      };
    };

    nix-templates = {
      url = "github:kleinbem/nix-templates";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
      };
    };

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    jetpack-nixos = {
      url = "github:anduril/jetpack-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      flake = {
        inherit (inputs.nix-config) nixosConfigurations diskoConfigurations nixOnDroidConfigurations;
      };
      perSystem =
        { system, lib, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              (_: prev: {
                libghostty-vt = (inputs.ghostty.packages.${system} or { }).libghostty-vt or prev.hello;
              })
            ];
          };
          packagesFromPresets = inputs.nix-presets.packages.${system} or { };
          packagesFromPackages = inputs.nix-packages.packages.${system} or { };
        in
        {
          devenv.modules = [
            (_: {
              overlays = [
                (_: prev: {
                  libghostty-vt = (inputs.ghostty.packages.${system} or { }).libghostty-vt or prev.hello;
                })
              ];
            })
          ];

          _module.args.pkgs = pkgs;
          packages = packagesFromPackages // packagesFromPresets;

          devenv.shells = {
            default = {
              imports = [ ./devenv.nix ];
              _module.args.inputs = inputs;
            };

            apps = {
              imports = [ inputs.nix-devshells.devenvModules.apps ];
              devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
              _module.args.inputs = inputs;
              _module.args.system = system;
            };

            pentest = {
              imports = [ inputs.nix-devshells.devenvModules.pentest ];
              devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
              _module.args.inputs = inputs;
              _module.args.system = system;
            };

            ai-dev = {
              imports = [ inputs.nix-devshells.devenvModules.ai-dev ];
              devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
              _module.args.inputs = inputs;
              _module.args.system = system;
            };

            math = {
              imports = [ inputs.nix-devshells.devenvModules.math ];
              devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
              _module.args.inputs = inputs;
              _module.args.system = system;
            };

            media = {
              imports = [ inputs.nix-devshells.devenvModules.media ];
              devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
              _module.args.inputs = inputs;
              _module.args.system = system;
            };

            ultimate = {
              imports = [
                inputs.nix-devshells.devenvModules.apps
                inputs.nix-devshells.devenvModules.pentest
                inputs.nix-devshells.devenvModules.ai-dev
                inputs.nix-devshells.devenvModules.math
                inputs.nix-devshells.devenvModules.media
              ];
              devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
              _module.args.inputs = inputs;
              _module.args.system = system;

              env = {
                DEV_SHELL_NAME = lib.mkForce "ultimate";
                STARSHIP_SHELL_SYMBOL = lib.mkForce "🌌 ";
                WORDLISTS = lib.mkForce "${inputs.nixpkgs.legacyPackages.${system}.seclists}/share/wordlists";
              };
              scripts.inventory.exec = lib.mkForce ''
                echo "$STARSHIP_SHELL_SYMBOL $DEV_SHELL_NAME Inventory (Live Audit):"
                # Filter for primary binaries (ignore versioned duplicates, aliases, and internal scripts)
                ls $DEVENV_PROFILE/bin | grep -vE "(-[0-9]|\.sh|@|pkg-config|inventory|process-compose|crityp|typlite|mkoctfile|octave-config)" | sort -u | while read bin; do
                  # SMOKE TEST: Try to get version, if it fails completely, mark as NOK
                  version_raw=$($bin --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
                  if [ $? -eq 0 ]; then
                    printf "  ✅ %-15s (%s)\n" "$bin" "''${version_raw:-active}"
                  else
                    printf "  ❌ %-15s (BROKEN)\n" "$bin"
                  fi
                done
              '';
              enterShell = "inventory";
            };
          };

          devShells.ai = inputs.nix-devshells.devShells.${system}.ai;

          formatter = inputs.nix-devshells.formatter.${system};

          # ---------------------------------------------------------
          # Aggregated Workspace Checks
          # ---------------------------------------------------------
          # Combines checks from all sub-flakes to allow 'nix flake check'
          # at the root to verify the entire workspace.
          checks =
            (inputs.nix-config.checks.${system} or { })
            // (inputs.nix-presets.checks.${system} or { })
            // (inputs.nix-packages.checks.${system} or { })
            // (inputs.nix-devshells.checks.${system} or { })
            // (inputs.nix-templates.checks.${system} or { });
        };
    };
}
