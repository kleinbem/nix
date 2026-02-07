#!/usr/bin/env bash
set -e

# Resolve directory
MY_DIR="$(dirname "$(realpath "$0")")"

echo "--------------------------------------------------------"
echo "Phase 2: Waydroid Configuration (Post-Install)"
echo "--------------------------------------------------------"

# Ensure Waydroid is running
if ! waydroid status | grep -q "RUNNING"; then
    echo "Waydroid is NOT running."
    echo "Starting Waydroid Service..."
    sudo systemctl restart waydroid-container
    echo "Waiting for session..."
    waydroid session start &
    sleep 10
fi

# 1. Update Play Integrity Fix
echo "--------------------------------------------------------"
echo "Updating Play Integrity Fix..."
"$MY_DIR/update-play-integrity.sh"

# 2. Set Properties
echo "--------------------------------------------------------"
echo "Setting Default Window Size (Phone Layout)..."
sudo waydroid prop set persist.waydroid.width 600
sudo waydroid prop set persist.waydroid.height 1200
# Enable Fake WiFi
sudo waydroid prop set persist.waydroid.fake_wifi true
echo "Resolution set: 600x1200 | Fake WiFi: Enabled"

echo "--------------------------------------------------------"
echo "Configuration Complete!"
echo "You can now launch the UI: waydroid show-full-ui"
