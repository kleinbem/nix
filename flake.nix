{
  description = "Meta-Workspace for Nix Repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";

    # Import Local Devshell to keep tools consistent
    nix-devshells.url = "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells";
    nix-devshells.inputs.devenv.follows = "devenv";
    nix-devshells.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, system, ... }:
        {
          devenv.shells.default = {
            imports = [ inputs.nix-devshells.devenvModules.default ];

            # FORCE the root to be the current directory (mutable)
            devenv.root = "/home/martin/Develop/github.com/kleinbem/nix";
          };

          formatter = inputs.nix-devshells.formatter.${system};
        };
    };
}
