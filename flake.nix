{
  description = "Meta-Workspace for Nix Repositories";

  inputs = {
    # Tracking nixos-unstable to pull in latest upstream fixes for COSMIC:
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";

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

  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      flake = {
        inherit (inputs.nix-config) nixosConfigurations diskoConfigurations;
      };
      perSystem =
        { system, ... }:
        let
          packagesFromPresets = inputs.nix-presets.packages.${system} or { };
          packagesFromPackages = inputs.nix-packages.packages.${system} or { };
        in
        {
          packages = packagesFromPackages // packagesFromPresets;

          devenv.shells.default = {
            imports = [ ./devenv.nix ];
            _module.args.inputs = inputs;
          };

          devShells.ai = inputs.nix-devshells.devShells.${system}.ai;

          formatter = inputs.nix-devshells.formatter.${system};
        };
    };
}
