#!/usr/bin/env bash
# tools/phone-backup.sh
# Run this ON THE PHONE to create a snapshot of the working environment.
# The snapshot holds secrets (dashboard credentials, ssh keys), so it's encrypted
# to the fleet's YubiKeys before it touches shared storage. Restore on a PC:
#   age -d -i <(age-plugin-yubikey --identity) nix-on-droid-snapshot-<date>.tar.age | tar -x

set -euo pipefail

# Same recipients as the fleet backups (nix-config modules/nixos/keys.nix, age.yubikey-*).
RECIPIENTS=(
  age1yubikey1q2lhmqc0h6verf025hn62tkjkz25d760h54pdej7a55q4m2hszm8kwssfn0
  age1yubikey1qg379rzgajvstx6vhk2fsvc0eu9zyjjk7q24pd3pf5dq22xvlqew23e08l2
)
BACKUP_NAME="/sdcard/Download/nix-on-droid-snapshot-$(date +%F).tar.age"

echo "📦 Finding tar binary..."
# shellcheck disable=SC2012
TAR=$(ls /nix/store/*gnutar*/bin/tar 2>/dev/null | head -n 1) || true
if [ -z "$TAR" ]; then
  echo "❌ No gnutar in /nix/store." >&2
  exit 1
fi
# age needs age-plugin-yubikey to encrypt to YubiKey recipients (no key needed for that).
for bin in age age-plugin-yubikey; do
  if ! command -v "$bin" >/dev/null; then
    echo "❌ $bin not on PATH (nix-config's nix-on-droid dashboard module installs it); nothing written." >&2
    exit 1
  fi
done
age_args=()
for r in "${RECIPIENTS[@]}"; do age_args+=(-r "$r"); done

echo "📂 Moving to app root..."
cd /data/data/com.termux.nix/files

echo "🛡️ Creating encrypted snapshot (excluding problematic /usr loops)..."
echo "Target: $BACKUP_NAME"

# Only /nix and /home: /usr has symlink loops that crash tar.
# Written under a temporary name, so a failed run leaves no half-written snapshot.
partial="$BACKUP_NAME.partial"
trap 'rm -f "$partial"' EXIT
"$TAR" -cf - ./nix ./home | age "${age_args[@]}" -o "$partial"
mv "$partial" "$BACKUP_NAME"
trap - EXIT

echo "✅ Encrypted snapshot created!"
echo "💡 TIP: Copy it to your PC for safekeeping, then delete it from the phone: 'adb pull $BACKUP_NAME . && adb shell rm $BACKUP_NAME'"
