let
  flake = builtins.getFlake "path:/home/martin/Develop/github.com/kleinbem/nix/nix-devshells";
  system = "x86_64-linux";
  ghosttyPkgs = flake.inputs.devenv.inputs.ghostty.packages.${system} or { };
in
builtins.attrNames ghosttyPkgs
