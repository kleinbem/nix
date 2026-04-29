#!/usr/bin/env bash
set -e

echo "=== MemTest86+ USB Creator ==="

# We use the open-source MemTest86+ v7 (which supports UEFI Secure Boot off).
MEMTEST_URL="https://memtest.org/download/v7.20/mt86plus_7.20.iso"
ISO_FILE="/tmp/memtest86plus.iso"

if [ -z "$1" ]; then
  echo "Usage: sudo $0 /dev/sdX"
  echo "Available USB drives:"
  lsblk -d -o NAME,SIZE,MODEL | grep -v 'nvme\|loop' || true
  exit 1
fi

DEVICE=$1

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (sudo)."
  exit 1
fi

echo ""
echo "WARNING: All data on $DEVICE will be destroyed!"
echo "Please double-check that this is a USB drive, not a system drive."
lsblk "$DEVICE"
echo ""

read -p "Are you absolutely sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

echo "Downloading MemTest86+ ISO..."
curl -L -o "$ISO_FILE" "$MEMTEST_URL"

echo "Flashing to $DEVICE... (this may take a moment)"
dd if="$ISO_FILE" of="$DEVICE" bs=4M status=progress
sync

echo ""
echo "Done! The USB drive is ready."
echo "To boot: Restart the system, enter your BIOS/UEFI boot menu (usually F12, F11, or F8), and select the USB drive."
echo "Note: Since Lanzaboote (Secure Boot) is enabled on your host, you may need to temporarily DISABLE Secure Boot in your BIOS to launch MemTest86+."
