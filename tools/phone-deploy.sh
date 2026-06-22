#!/usr/bin/env bash
# tools/phone-deploy.sh
# Automates packaging and pushing the entire meta-repo to Nix-on-Droid.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARBALL="/tmp/nix-full.tar.gz"

echo "🔄 Updating flake lock for nix-config..."
cd "$REPO_ROOT/nix-config"
nix flake lock

echo "📦 Packaging meta-repo repositories..."
cd "$REPO_ROOT"
tar czf "$TARBALL" \
  --exclude='.git' \
  --exclude='.devenv' \
  --exclude='.tools' \
  --exclude='result' \
  --exclude='nix-config/result' \
  nix-config/ nix-presets/ nix-devshells/ nix-hardware/ nix-packages/ nix-templates/ nix-secrets/ tools/

echo "📲 Pushing to phone via ADB..."
adb push "$TARBALL" /sdcard/Download/

echo "🚀 Triggering automatic update on phone..."
# We use a single large ADB command to handle the whole process remotely
adb shell "
  set -e
  HOME_DIR=/data/data/com.termux.nix/files/home
  
  # 1. Find extraction tools
  TAR=\$(ls /nix/store/*gnutar*/bin/tar | head -n 1)
  GZIP=\$(ls /nix/store/*gzip*/bin/gzip | head -n 1)
  
  # 2. Extract directly from public storage
  # (Requires termux-setup-storage to have been run once on the phone)
  echo '📦 Extracting meta-repo...'
  # Clean both old (scripts/) and new (tools/) names for backward compat on
  # phones still holding the pre-rename tarball layout.
  rm -rf \$HOME_DIR/scripts \$HOME_DIR/tools
  \$TAR --use-compress-program=\$GZIP -xf /sdcard/Download/nix-full.tar.gz -C \$HOME_DIR

  # 3. Activate (this handles git, building, and symlinks)
  bash \$HOME_DIR/tools/phone-activate.sh
"

echo "✅ ALL DONE! Your phone is now updated and active."
