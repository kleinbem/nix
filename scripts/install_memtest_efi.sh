#!/usr/bin/env bash
set -e

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (sudo)."
  exit 1
fi

echo "=== Installing MemTest86+ to systemd-boot ==="

# Build or fetch the memtest86+ EFI binary from nixpkgs
echo "Fetching MemTest86+ from nixpkgs..."
MEMTEST_STORE_PATH=$(nix-build '<nixpkgs>' -A memtest86plus --no-out-link)
EFI_SRC="$MEMTEST_STORE_PATH/mt86plus.efi"

# Systemd-boot automatically discovers tools in EFI/tools/
TOOLS_DIR="/boot/EFI/tools"
EFI_DST="$TOOLS_DIR/memtest.efi"

mkdir -p "$TOOLS_DIR"
echo "Copying MemTest EFI binary..."
cp "$EFI_SRC" "$EFI_DST"

echo "Signing MemTest with sbctl for Secure Boot..."
sbctl sign -s "$EFI_DST"

echo ""
echo "Done! MemTest86+ is now installed in systemd-boot and signed for Lanzaboote."
echo "To use it: Reboot, press the Spacebar or Down Arrow repeatedly during boot to show the systemd-boot menu, and select 'memtest'."
