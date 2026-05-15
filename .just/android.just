import 'common.just'

set working-directory := ".."

# --- Android / Phone & Tablet Management ---

PHONE_SERIAL  := "R5CW617ZWCF"
TABLET_SERIAL := "R52R70HSE9T"
PHONE_IP      := "10.0.0.8"
TABLET_IP     := "10.0.0.56"
DHIRUJAAN_PHONE_SERIAL := "RFCT90BVPNE"
DHIRUJAAN_PHONE_IP     := "10.0.0.238"

# ==========================================
# SMART DISPATCHERS (The "Single Entry" way)
# ==========================================

[group("Phone")]
phone *args:
    @just android::scrcpy-dispatch "{{PHONE_SERIAL}}" "{{PHONE_IP}}" "16M" {{args}}

[group("Tablet")]
tablet *args:
    @just android::scrcpy-dispatch "{{TABLET_SERIAL}}" "{{TABLET_IP}}" "24M" {{args}}

[group("Dhirujaan")]
dhirujaan *args:
    @just android::scrcpy-dispatch "{{DHIRUJAAN_PHONE_SERIAL}}" "{{DHIRUJAAN_PHONE_IP}}" "16M" {{args}}

# ==========================================
# PRIVATE HELPERS (Logic Core)
# ==========================================

[private]
scrcpy-dispatch serial ip bitrate *args:
    #!/usr/bin/env bash
    set -e
    MODE="usb"
    AUDIO_FLAG=""
    
    # Parse Arguments
    for arg in {{args}}; do
        case $arg in
            wireless) MODE="wireless" ;;
            silent)   AUDIO_FLAG="--no-audio" ;;
            dup)      AUDIO_FLAG="--audio-dup" ;;
            help|-h|--help)
                echo "📱 scrcpy Smart Dispatcher"
                echo "--------------------------------"
                echo "Usage: just <command> [options]"
                echo ""
                echo "Options:"
                echo "  wireless  - Connect via TCP/IP (auto-connects if needed)"
                echo "  silent    - Launch without audio (--no-audio)"
                echo "  dup       - Mirror audio on both device and PC (--audio-dup)"
                echo "  help      - Show this help menu"
                exit 0
                ;;
            *)
                echo "⚠️ Unknown option: $arg"
                echo "💡 Available options: wireless, silent, dup, help"
                exit 1
                ;;
        esac
    done

    # Auto-detect Mode if USB is missing
    if [ "$MODE" == "usb" ] && ! adb devices | grep -q "{{serial}}"; then
        echo "🔌 USB device {{serial}} not found. Falling back to wireless..."
        MODE="wireless"
    fi

    if [ "$MODE" == "wireless" ]; then
        echo "📡 Checking for device at {{ip}}..."
        if ! adb devices | grep -q "{{ip}}:5555"; then
            echo "🔄 Initializing wireless bridge..."
            adb -s {{serial}} tcpip 5555 2>/dev/null || true
            sleep 2
            adb connect {{ip}}
        fi
        echo "🚀 Launching Wireless scrcpy ({{bitrate}})..."
        scrcpy --tcpip={{ip}} --max-fps 60 --video-bit-rate {{bitrate}} --stay-awake --power-off-on-close $AUDIO_FLAG
    else
        echo "🚀 Launching USB scrcpy ({{bitrate}})..."
        scrcpy -s {{serial}} --max-fps 60 --video-bit-rate {{bitrate}} --stay-awake --power-off-on-close $AUDIO_FLAG
    fi

# ==========================================
# MAINTENANCE & UTILS
# ==========================================

[group("Maintenance")]
android-sync:
    @echo "🔄 Syncing phone configuration locks..."
    @nix flake lock --update-input nix-config
    @git add flake.lock
    @git commit -m "chore(phone): sync nix-config lock" || echo "Already synced."
    @git push

[group("Maintenance")]
android-deploy:
    @just android::android-sync
    @echo "📡 Triggering update on phone via ADB..."
    @adb -s {{PHONE_SERIAL}} shell "export PATH=\$PATH:/data/data/com.termux.nix/files/home/.nix-profile/bin; cd ~/nix && git pull && nix-on-droid switch --flake .#phone --impure"

[group("Maintenance")]
android-backup:
    @echo "📥 Fetching latest Nix-on-Droid backups..."
    @adb pull "/sdcard/Download/nix-on-droid-snapshot-*.tar" . || echo "No snapshot found."

# Keeping the hub for discovery
[group("Hub")]
android-hub:
    #!/usr/bin/env bash
    CHOICES="phone\ntablet\ndhirujaan\nandroid-sync\nandroid-deploy\nandroid-backup"
    echo -e "$CHOICES" | fzf --header "📱 scrcpy Hub" --height 15 --reverse --preview "just --show {}" | xargs -r just

