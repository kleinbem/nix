#!/usr/bin/env bash
# scripts/phone-activate.sh
# To be run ON THE PHONE inside the nix-config directory.
# Automates Git initialization, Nix building with overrides, and the PTY-bypass symlink.

set -e

echo "🔍 Finding Git in the Nix store..."
GIT=$(ls /nix/store/*git-2*/bin/git | head -n 1)
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
    --override-input nix-secrets ../nix-secrets \
    |& cat

echo "🏁 Applying Manual PTY Bypass (Atomic Switch)..."
CONF_PATH=$(readlink -f ./result)
# Link the profile
ln -sfn "$CONF_PATH" /nix/var/nix/profiles/nix-on-droid-path

# Find the nested bin folder (XCover 6 Pro / Nix-on-Droid specific structure)
NESTED_BIN=$(ls -d /nix/var/nix/profiles/nix-on-droid-path/*/bin | head -n 1)

echo "🔗 Linking core binaries from $NESTED_BIN..."
mkdir -p /data/data/com.termux.nix/files/usr/bin
ln -sfn "$NESTED_BIN/sh" /data/data/com.termux.nix/files/usr/bin/sh
ln -sfn "$NESTED_BIN/env" /data/data/com.termux.nix/files/usr/bin/env

echo "✨ Success! Run 'zsh' to enter your new environment."
echo "💡 TIP: If the app fails to boot, use the Fail-safe shortcut (Long-press icon) and run this script again."
