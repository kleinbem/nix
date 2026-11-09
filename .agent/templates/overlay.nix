# deadnix: skip # the commented example below uses pkgs once uncommented
{ pkgs, ... }:

{
  # If this package is from GitHub/GitLab
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     my-package = prev.callPackage ./pkgs/my-package { };
  #   })
  # ];

  # Or creating a simple shell script wrapper
  # environment.systemPackages = [
  #   (pkgs.writeShellScriptBin "my-script" ''
  #     echo "Hello World"
  #   '')
  # ];
}
