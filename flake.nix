{
  description = "Meta-Workspace for Nix Repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-secrets = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-secrets";
      flake = false;
    };

    # Import Local Devshell to keep tools consistent
    nix-devshells = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells";
      inputs = {
        devenv.follows = "devenv";
        nixpkgs.follows = "nixpkgs";
        nixos-generators.follows = "nixos-generators";
      };
    };

    # Import NixOS Config to expose systems at root
    nix-config = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-config";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
        nix-hardware.follows = "nix-hardware";
        nix-presets.follows = "nix-presets";
        nix-packages.follows = "nix-packages";
        nix-templates.follows = "nix-templates";
        sops-nix.follows = "sops-nix";
        home-manager.follows = "home-manager";
        nixpak.follows = "nixpak";
        colmena.follows = "colmena";
        nix-secrets.follows = "nix-secrets";
      };
    };

    nix-presets = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-presets";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
        nixpak.follows = "nixpak";
      };
    };

    nix-hardware = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-hardware";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
      };
    };

    nix-packages = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-packages";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-devshells.follows = "nix-devshells";
      };
    };

    nix-templates = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-templates";
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
            imports = [ inputs.nix-devshells.devenvModules.default ];

            # FORCE the root to be the current directory (mutable)
            devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";

            # Pass inputs so the shell module can access nixos-generators etc.
            _module.args.inputs = inputs;
          };

          devShells.ai = inputs.nix-devshells.devShells.${system}.ai;

          formatter = inputs.nix-devshells.formatter.${system};
        };
    };
}
