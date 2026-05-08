# System Architecture: nixos-nvme

## Hardware Layer
- **CPU**: Intel (Microcode updates enabled)
- **GPU**: Intel Integrated (iHD driver, Libva enabled)
- **RAM**: zRam Swap enabled (zstd, 25%)
- **Boot**: Systemd-boot (Limit: 8 generations)

## Core Software
- **OS**: NixOS Unstable (25.11 State Version)
- **Desktop Environment**: COSMIC (Wayland)
- **Window Management**: XWayland enabled
- **Virtualization**: Podman (Docker compatibility enabled)

## Peripherals & Drivers
- **Printing**: Ricoh SP 220Nw
  - **Driver**: Custom Derivation (`ricoh-driver.nix` wrapping RPM)
  - **Connection**: Socket 9100 (Static IP: 10.0.5.10)

## Security & Sandboxing
- **Framework**: Nixpak (Bubblewrap)
- **Sandboxed Apps**: 
  - Obsidian (Binder: ~/Documents)
  - Google Chrome (Binder: ~/Downloads, /dev/video)
- **Secrets**: Sops-Nix (Ready for integration)

## User Space
- **User**: martin
- **Home Manager**: Enabled (24.11 State Version)
- **Key Apps**: Cosmic Suite, VSCode FHS, Neovim