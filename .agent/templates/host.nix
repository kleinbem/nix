{ ... }:

{
  imports = [
    # Hardware config (auto-generated)
    ./hardware-configuration.nix

    # Base configuration (shared by all machines)
    ../../modules/nixos/base

    # Role-specific modules
    # ../../modules/nixos/desktop/gnome
    # ../../modules/nixos/roles/gaming
  ];

  # Machine-specific settings
  networking.hostName = "hostname";

  # Bootloader setup (Standard UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
