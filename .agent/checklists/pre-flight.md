# Pre-Flight Checklist: New Machine Setup

## BIOS / Firmware

- [ ] Secure Boot: [Disabled] (Unless using lanzaboote)
- [ ] Fast Boot: [Disabled]
- [ ] SATA Mode: [AHCI]
- [ ] TPM: [Enabled]

## Disk Layout

- [ ] Declare the disks in a disko layout (`hosts/<name>/disko.nix` or a shared one in
      `modules/nixos/`). disko partitions, formats and mounts the target, so the fleet
      doesn't use `nixos-generate-config` or a hand-written `hardware-configuration.nix`.

## Add the Host

Work in `nix-config` (a sibling of `nix/`, not inside it).

- [ ] Follow `nix-config/hosts/AGENTS.md` and the host checklist in
      `nix-config/docs/DEVICE-TIERS.md` (inventory entry, host dir, nix-hardware module).
- [ ] `just dev::sync-agent` and `just dev::check-hosts` in `nix-config`.

## Install

- [ ] Use the host's install recipe in `nix-config` (`just --list deployment`: `*-install-usb`,
      `orin-promote`). They run disko and install `nix-config#<name>`; for a new kind of host,
      copy the closest one. Read the recipe first: they wipe the target disk, and
      `pi-install-usb` is broken (kleinbem/nix-config#633).
