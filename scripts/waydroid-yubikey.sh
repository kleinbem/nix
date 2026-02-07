#!/usr/bin/env bash
set -e

CONFIG_FILE="/var/lib/waydroid/lxc/waydroid/config"

case "$1" in
    "enable")
        echo "Enabling YubiKey passthrough for Waydroid..."
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "Error: Waydroid config not found. Is Waydroid initialized?"
            exit 1
        fi
        
        # Ensure AppArmor is unconfined (Fixes the hang/dev/null error)
        if ! grep -q "lxc.apparmor.profile = unconfined" "$CONFIG_FILE"; then
            sudo sed -i '$a lxc.apparmor.profile = unconfined' "$CONFIG_FILE"
        fi

        # Add YubiKey rules
        if ! grep -q "uhid" "$CONFIG_FILE"; then
            sudo sed -i '$a lxc.cgroup2.devices.allow = c 10:239 rwm' "$CONFIG_FILE"
            sudo sed -i '$a lxc.mount.entry = /dev/uhid dev/uhid none bind,optional,create=file' "$CONFIG_FILE"
            echo "Added YubiKey rules to LXC config."
        else
            echo "YubiKey rules already present."
        fi
        
        echo "Restarting Waydroid to apply changes..."
        sudo systemctl restart waydroid-container
        ;;
    "disable")
        echo "Disabling YubiKey passthrough for Waydroid..."
        if [ -f "$CONFIG_FILE" ]; then
            sudo sed -i '/uhid/d' "$CONFIG_FILE"
            # Keep the apparmor fix even when disabling YubiKey
            if ! grep -q "lxc.apparmor.profile = unconfined" "$CONFIG_FILE"; then
                sudo sed -i '$a lxc.apparmor.profile = unconfined' "$CONFIG_FILE"
            fi
            echo "Removed YubiKey rules from LXC config."
        fi
        
        echo "Restarting Waydroid to apply changes..."
        sudo systemctl restart waydroid-container
        ;;
    *)
        echo "Usage: $0 {enable|disable}"
        exit 1
        ;;
esac
