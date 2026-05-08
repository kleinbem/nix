{
  pkgs ? import <nixpkgs> { },
}:
{
  clapgrep = pkgs ? clapgrep;
  devtoolbox = pkgs ? devtoolbox;
  podman-desktop = pkgs ? podman-desktop;
  gnome-builder = pkgs ? gnome-builder;
  distrobox = pkgs ? distrobox;
  boxbuddy = pkgs ? boxbuddy; # GUI for distrobox
  embellish = pkgs ? embellish;
}
