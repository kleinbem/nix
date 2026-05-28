#!/usr/bin/env bash
# scripts/phone-backup.sh
# Run this ON THE PHONE to create a safe snapshot of your working environment.

set -e

BACKUP_NAME="/sdcard/Download/nix-on-droid-snapshot-$(date +%F).tar"

echo "📦 Finding tar binary..."
# shellcheck disable=SC2012
TAR=$(ls /nix/store/*gnutar*/bin/tar | head -n 1)

echo "📂 Moving to app root..."
cd /data/data/com.termux.nix/files

echo "🛡️ Creating snapshot (excluding problematic /usr loops)..."
echo "Target: $BACKUP_NAME"

# We only backup /nix and /home to avoid symlink loop crashes in /usr
$TAR -cvf "$BACKUP_NAME" ./nix ./home

echo "✅ Snapshot created successfully!"
echo "💡 TIP: Copy this file to your PC for safekeeping: 'adb pull $BACKUP_NAME .'"
