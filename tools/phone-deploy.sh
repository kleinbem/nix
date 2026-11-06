#!/usr/bin/env bash
# tools/phone-deploy.sh
# Automates packaging and pushing the entire meta-repo to Nix-on-Droid.

set -euo pipefail

NIX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# nix-config et al are flat siblings of nix/, not nested under it — see repos.nix.
WORKSPACE_ROOT="$(dirname "$NIX_ROOT")"
TARBALL="$(mktemp -d)/nix-full.tar.gz"
# The tarball carries kleinbem-secrets (sops-encrypted) and the whole config:
# remove it from the PC and from the phone's shared storage however the run ends.
PHONE_TARBALL=/sdcard/Download/nix-full.tar.gz
pushed=
cleanup() {
  rm -rf "$(dirname "$TARBALL")"
  [ -n "$pushed" ] || return 0
  adb shell rm -f "$PHONE_TARBALL" >/dev/null 2>&1 || echo "⚠️ Couldn't remove $PHONE_TARBALL from the phone; delete it by hand." >&2
}
trap cleanup EXIT

echo "🔄 Updating flake lock for nix-config..."
cd "$WORKSPACE_ROOT/nix-config"
nix flake lock

echo "📦 Packaging meta-repo repositories..."
# Sources span two real directories (WORKSPACE_ROOT for the sub-repos,
# NIX_ROOT for tools/) but must land flat in the tarball — same layout
# tools/phone-activate.sh expects on the phone side.
tar czf "$TARBALL" \
  --exclude='.git' \
  --exclude='.jj' \
  --exclude='.direnv' \
  --exclude='.devenv' \
  --exclude='.tools' \
  --exclude='result' \
  -C "$WORKSPACE_ROOT" nix-config nix-presets nix-devshells nix-hardware nix-packages nix-templates kleinbem-secrets \
  -C "$NIX_ROOT" tools

echo "📲 Pushing to phone via ADB..."
pushed=1
adb push "$TARBALL" "$PHONE_TARBALL"

echo "🚀 Triggering automatic update on phone..."
# We use a single large ADB command to handle the whole process remotely
adb shell "
  set -e
  HOME_DIR=/data/data/com.termux.nix/files/home
  
  # 1. Find extraction tools
  TAR=\$(ls /nix/store/*gnutar*/bin/tar | head -n 1)
  GZIP=\$(ls /nix/store/*gzip*/bin/gzip | head -n 1)
  if [ -z \"\$TAR\" ] || [ -z \"\$GZIP\" ]; then
    echo '❌ tar or gzip not found in /nix/store; old tools left in place.' >&2
    exit 1
  fi
  
  # 2. Extract directly from public storage
  # (Requires termux-setup-storage to have been run once on the phone)
  echo '📦 Extracting meta-repo...'
  # Clean both old (scripts/) and new (tools/) names for backward compat on
  # phones still holding the pre-rename tarball layout.
  rm -rf \$HOME_DIR/scripts \$HOME_DIR/tools
  \$TAR --use-compress-program=\$GZIP -xf $PHONE_TARBALL -C \$HOME_DIR

  # 3. Activate (this handles git, building, and symlinks)
  bash \$HOME_DIR/tools/phone-activate.sh
"

echo "✅ ALL DONE! Your phone is now updated and active."
