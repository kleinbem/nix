#!/usr/bin/env bash
# tools/phone-activate.sh
# To be run ON THE PHONE inside the nix-config directory.
# Automates Git initialization, Nix building with overrides, and the PTY-bypass symlink.

set -euo pipefail

echo "🔍 Finding Git in the Nix store..."
# shellcheck disable=SC2012
GIT=$(ls /nix/store/*git-2*/bin/git 2>/dev/null | head -n 1) || true
if [ -z "$GIT" ]; then
  echo "❌ Git not found! Trying to run it via nix-run..."
  GIT="nix run nixpkgs#git --"
fi

echo "🔄 Initializing Git repositories for all components..."
cd ~/nix-config
for d in nix-*; do
  if [ -d "$d" ]; then
    echo "  -> Setting up $d..."
    cd "$d"
    $GIT init >/dev/null 2>&1 || true
    $GIT add . >/dev/null 2>&1 || true
    cd ..
  fi
done

echo "🏗️ Building activation package (with local overrides)..."
cd ~/nix-config
nix build ".#nixOnDroidConfigurations.phone.activationPackage" --impure \
  --override-input nix-config . \
  --override-input nix-presets ../nix-presets \
  --override-input nix-devshells ../nix-devshells \
  --override-input nix-hardware ../nix-hardware \
  --override-input nix-packages ../nix-packages \
  --override-input nix-templates ../nix-templates \
  --override-input kleinbem-secrets ../kleinbem-secrets |&
  cat

echo "🏁 Applying Manual PTY Bypass (Atomic Switch)..."
CONF_PATH=$(readlink -f ./result)

# Find the nested bin folder (XCover 6 Pro / Nix-on-Droid specific structure).
# Checked in the new build before the profile moves, since the core links
# resolve through the profile.
# shellcheck disable=SC2012
NEW_BIN=$(ls -d "$CONF_PATH"/*/bin 2>/dev/null | head -n 1) || true
if [ -z "$NEW_BIN" ] || [ ! -x "$NEW_BIN/sh" ] || [ ! -x "$NEW_BIN/env" ]; then
  echo "❌ No bin/ with sh and env in $CONF_PATH; profile and core links left as they were." >&2
  exit 1
fi
NESTED_BIN="/nix/var/nix/profiles/nix-on-droid-path/${NEW_BIN#"$CONF_PATH"/}"

# Link the profile
ln -sfn "$CONF_PATH" /nix/var/nix/profiles/nix-on-droid-path

echo "🔗 Linking core binaries from $NESTED_BIN..."
mkdir -p /data/data/com.termux.nix/files/usr/bin
ln -sfn "$NESTED_BIN/sh" /data/data/com.termux.nix/files/usr/bin/sh
ln -sfn "$NESTED_BIN/env" /data/data/com.termux.nix/files/usr/bin/env

echo "✨ Success! Run 'zsh' to enter your new environment."
echo "💡 TIP: If the app fails to boot, use the Fail-safe shortcut (Long-press icon) and run this script again."
