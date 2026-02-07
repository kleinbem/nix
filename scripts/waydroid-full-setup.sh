#!/usr/bin/env bash
set -e

SCRIPT_DIR="$HOME/.local/share/waydroid_script"
# Resolve directory now before we cd anywhere
MY_DIR="$(dirname "$(realpath "$0")")"

echo "!!! WARNING: This will DELETE ALL Waydroid data and start fresh !!!"
echo "Press Ctrl+C within 5 seconds to cancel..."
sleep 5

echo "--------------------------------------------------------"
echo "Step 0: Nuclear Reset (Cleaning old installation)"
echo "--------------------------------------------------------"
sudo waydroid session stop || true
sudo systemctl stop waydroid-container || true
# Remove user data (factory reset)
sudo rm -rf /var/lib/waydroid/data
sudo rm -rf ~/.local/share/waydroid/data

# Check if images exist. If not, download them.
if [ ! -f "/var/lib/waydroid/images/system.img" ]; then
    echo "Images missing. Downloading fresh images..."
    # Remove partials
    sudo rm -rf /var/lib/waydroid/images
    if ! sudo waydroid init -f -c https://ota.waydro.id/system -s VANILLA; then
        echo "ERROR: Waydroid Init failed! Could not download images."
        exit 1
    fi
else
    echo "System images found. Skipping download."
    # We still run init to ensure config is valid, but without -f (force) it should be safe/fast?
    # Actually, better to skip init if images exist to avoid overwriting configs unnecessarily.
    # But we need to ensure binder/nodes are initialized.
    sudo waydroid init -s VANILLA
fi

# 1. Clone/Update casualsnek script
if [ ! -d "$SCRIPT_DIR" ]; then
    echo "Cloning waydroid_script..."
    git clone https://github.com/casualsnek/waydroid_script "$SCRIPT_DIR"
else
    echo "Updating waydroid_script..."
    cd "$SCRIPT_DIR" && git pull || true
fi

# 2. Run the python installer (using nix-shell for dependencies)
# We use the exact nix-shell environment that worked manually
echo "--------------------------------------------------------"
echo "Running Waydroid Installer (Magisk, Libhoudini, GApps)..."
echo "--------------------------------------------------------"
cd "$SCRIPT_DIR"
nix-shell -p python3 python3Packages.pip --run "bash -c 'python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt --ignore-installed && sudo env PATH=\$PATH .venv/bin/python3 main.py install magisk libhoudini gapps widevine smartdock'"

echo "--------------------------------------------------------"
echo "Installation Complete!"
echo "The system images have been patched successfully."
echo ""
echo "Please RESTART your computer or restart the waydroid service manually to clear loop devices:"
echo "  sudo systemctl restart waydroid-container"
echo ""
echo "After restarting, run:"
echo "  just waydroid-configure"
echo "To finish the setup (Play Integrity, Resolution, etc)."
echo "--------------------------------------------------------"
