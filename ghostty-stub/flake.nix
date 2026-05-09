{
  description = "Ghostty stub for devenv";
  outputs =
    { nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system: {
        libghostty-vt = nixpkgs.legacyPackages.${system}.hello;
      });
      overlays.default = _: prev: {
        libghostty-vt = prev.hello;
      };
    };
}
