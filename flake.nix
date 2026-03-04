{
  description = "Meta-Workspace for Nix Repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    # Import Local Devshell to keep tools consistent
    nix-devshells = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells";
      inputs.devenv.follows = "devenv";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-generators.follows = "nixos-generators";
    };

    # Import NixOS Config to expose systems at root
    nix-config = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-presets = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-presets";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-packages = {
      url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs";
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

          formatter = inputs.nix-devshells.formatter.${system};
        };
    };
}
