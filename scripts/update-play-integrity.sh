#!/usr/bin/env bash
set -e

echo "Fetching latest Play Integrity Fix URL..."

# Strategy: Fetch URL on host (better tools like curl/grep), then download INSIDE container
LATEST_URL=$(curl -s "https://api.github.com/repos/osm0sis/PlayIntegrityFork/releases/latest" | grep "browser_download_url" | head -n 1 | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    echo "API failed, using fallback URL..."
    LATEST_URL="https://github.com/osm0sis/PlayIntegrityFork/releases/download/v16/PlayIntegrityFork-v16.zip"
fi

echo "Target Download URL: $LATEST_URL"

echo "Downloading and Pushing to container via stream..."
# Clean up potential locked/root-owned temp files
rm -f /tmp/pif.zip || sudo rm -f /tmp/pif.zip

# Download to temp on host
if ! wget -q --show-progress -O /tmp/pif.zip "$LATEST_URL"; then
    echo "Download failed!"
    exit 1
fi

# Stream file into container using cat
# This avoids 'cp' path issues and uses stdin redirection properly
sudo waydroid shell -- /system/bin/sh -c "cat > /data/local/tmp/pif.zip" < /tmp/pif.zip

echo "Installing Module via Magisk..."
if sudo waydroid shell which magisk >/dev/null; then
    sudo waydroid shell -- /system/bin/sh -c "magisk --install-module /data/local/tmp/pif.zip"
    echo "--------------------------------------------------------"
    echo "SUCCESS: Module Installed from /data/local/tmp !"
    echo "Cleaning up..."
    sudo waydroid shell rm /data/local/tmp/pif.zip
    echo "Please Reboot Waydroid now: sudo systemctl restart waydroid-container"
    echo "--------------------------------------------------------"
else
    echo "WARNING: Magisk CLI not found!"
    exit 1
fi
