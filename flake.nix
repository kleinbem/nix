{
  description = "Meta-Workspace for Nix Repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Import Local Devshell to keep tools consistent
    nix-devshells.url = "git+file:./nix-devshells";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem =
        { pkgs, system, ... }:
        {
          devShells.default = pkgs.mkShell {
            inputsFrom = [ inputs.nix-devshells.devShells.${system}.default ];

            # just, lazygit, gh are now inherited from nix-devshells

            shellHook = ''
              echo "🚀 Meta-Workspace Loaded"
              echo "Type 'just' to see available commands."
            '';
          };

          formatter = inputs.nix-devshells.formatter.${system};
        };
    };
}
