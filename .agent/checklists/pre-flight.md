# Pre-Flight Checklist: New Machine Setup

## BIOS / Firmware

- [ ] Secure Boot: [Disabled] (Unless using lanzaboote)
- [ ] Fast Boot: [Disabled]
- [ ] SATA Mode: [AHCI]
- [ ] TPM: [Enabled]

## Disk Partitioning (Manual)

- [ ] EFI Partition (512MB-1GB, FAT32)
- [ ] Root Partition (Ext4/Btrfs/ZFS)
- [ ] Swap (Optional)

## Antigravity Bootstrap

- [ ] Clone Repo: `git clone ...`
- [ ] Generate Config: `nixos-generate-config`
- [ ] Update `hosts/<name>/hardware-configuration.nix` with UUIDs
- [ ] Run Bootstrap: `.agent/scripts/bootstrap.sh`
- [ ] Verify: `.agent/workflows/verify.md`
- [ ] Install: `nixos-install --flake .#<name>`
