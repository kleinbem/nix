import 'common.just'

set working-directory := ".."

# --- Android / Phone & Tablet Management ---

PHONE_SERIAL  := "R5CW617ZWCF"
TABLET_SERIAL := "R52R70HSE9T"
PHONE_IP      := "10.0.0.8"
TABLET_IP     := "10.0.0.56"
DHIRUJAAN_PHONE_SERIAL := "RFCT90BVPNE"
DHIRUJAAN_PHONE_IP     := "10.0.0.238"

[group("Phone")]
phone *args:
    @echo "📱 Launching scrcpy (Phone/USB)..."
    @scrcpy -s {{PHONE_SERIAL}} --max-fps 60 --video-bit-rate 16M --stay-awake --power-off-on-close {{args}}

[group("Phone")]
[private]
phone-dup:
    @just android::phone --audio-dup

[group("Phone")]
[private]
phone-silent:
    @just android::phone --no-audio

[group("Phone")]
phone-wireless *args:
    @echo "📡 Checking for phone IP..."
    @DETECTED_IP=$(adb -s {{PHONE_SERIAL}} shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1 || true); \
    IP=${DETECTED_IP:-"{{PHONE_IP}}"}; \
    echo "🔗 Phone IP: $IP"; \
    if ! adb devices | grep -q "$IP:5555"; then \
        echo "🔄 Initializing wireless bridge..."; \
        adb -s {{PHONE_SERIAL}} tcpip 5555 2>/dev/null || true; \
        sleep 2; \
        adb connect $IP; \
    fi; \
    echo "🚀 Launching wireless scrcpy..."; \
    scrcpy --tcpip=$IP --max-fps 60 --video-bit-rate 12M --stay-awake --power-off-on-close {{args}}

[group("Phone")]
[private]
phone-wireless-dup:
    @just android::phone-wireless --audio-dup

[group("Phone")]
[private]
phone-wireless-silent:
    @just android::phone-wireless --no-audio

[group("Phone")]
[private]
phone-ip:
    @DETECTED_IP=$(adb -s {{PHONE_SERIAL}} shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1 || true); \
    echo ${DETECTED_IP:-"{{PHONE_IP}}"}

# --- Dhirujaan's Phone Management ---

[group("Dhirujaan")]
dhirujaan-phone *args:
    @echo "📱 Launching scrcpy (Dhirujaan's Phone/USB)..."
    @scrcpy -s {{DHIRUJAAN_PHONE_SERIAL}} --max-fps 60 --video-bit-rate 16M --stay-awake --power-off-on-close {{args}}

[group("Dhirujaan")]
[private]
dhirujaan-phone-dup:
    @just android::dhirujaan-phone --audio-dup

[group("Dhirujaan")]
[private]
dhirujaan-phone-silent:
    @just android::dhirujaan-phone --no-audio

[group("Dhirujaan")]
dhirujaan-phone-wireless *args:
    @echo "📡 Checking for Dhirujaan's phone IP..."
    @DETECTED_IP=$(adb -s {{DHIRUJAAN_PHONE_SERIAL}} shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1 || true); \
    IP=${DETECTED_IP:-"{{DHIRUJAAN_PHONE_IP}}"}; \
    echo "🔗 Phone IP: $IP"; \
    if ! adb devices | grep -q "$IP:5555"; then \
        echo "🔄 Initializing wireless bridge..."; \
        adb -s {{DHIRUJAAN_PHONE_SERIAL}} tcpip 5555 2>/dev/null || true; \
        sleep 2; \
        adb connect $IP; \
    fi; \
    echo "🚀 Launching wireless scrcpy..."; \
    scrcpy --tcpip=$IP --max-fps 60 --video-bit-rate 12M --stay-awake --power-off-on-close {{args}}

[group("Dhirujaan")]
[private]
dhirujaan-phone-wireless-dup:
    @just android::dhirujaan-phone-wireless --audio-dup

[group("Dhirujaan")]
[private]
dhirujaan-phone-wireless-silent:
    @just android::dhirujaan-phone-wireless --no-audio

[group("Dhirujaan")]
[private]
dhirujaan-phone-ip:
    @DETECTED_IP=$(adb -s {{DHIRUJAAN_PHONE_SERIAL}} shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1 || true); \
    echo ${DHIRUJAAN_PHONE_IP}

# --- Tablet Management ---

[group("Tablet")]
tablet *args:
    @echo "📟 Launching scrcpy (Tablet/USB)..."
    @scrcpy -s {{TABLET_SERIAL}} --max-fps 60 --video-bit-rate 24M --stay-awake --power-off-on-close {{args}}

[group("Tablet")]
[private]
tablet-dup:
    @just android::tablet --audio-dup

[group("Tablet")]
[private]
tablet-silent:
    @just android::tablet --no-audio

[group("Tablet")]
tablet-wireless *args:
    @echo "📡 Checking for tablet IP..."
    @DETECTED_IP=$(adb -s {{TABLET_SERIAL}} shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1 || true); \
    IP=${DETECTED_IP:-"{{TABLET_IP}}"}; \
    echo "🔗 Tablet IP: $IP"; \
    if ! adb devices | grep -q "$IP:5555"; then \
        echo "🔄 Initializing wireless bridge..."; \
        adb -s {{TABLET_SERIAL}} tcpip 5555 2>/dev/null || true; \
        sleep 2; \
        adb connect $IP; \
    fi; \
    echo "🚀 Launching wireless scrcpy..."; \
    scrcpy --tcpip=$IP --max-fps 60 --video-bit-rate 16M --stay-awake --power-off-on-close {{args}}

[group("Tablet")]
[private]
tablet-wireless-dup:
    @just android::tablet-wireless --audio-dup

[group("Tablet")]
[private]
tablet-wireless-silent:
    @just android::tablet-wireless --no-audio

[group("Tablet")]
[private]
tablet-ip:
    @DETECTED_IP=$(adb -s {{TABLET_SERIAL}} shell ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1 || true); \
    echo ${TABLET_IP}

[group("Tablet")]
tablet-quiet:
    @echo "🔇 Lowering tablet volume..."
    @adb -s {{TABLET_SERIAL}} shell media volume --set 6

[group("Hub")]
android:
    #!/usr/bin/env bash
    CHOICES=$(just --summary | tr ' ' '\n' | grep -E '^(phone|tablet|dhirujaan)' | sort)
    if command -v fzf >/dev/null; then
        echo "$CHOICES" | fzf --header "📱 scrcpy Hub" --height 15 --reverse --preview "just --show {}" | xargs -r just
    else
        echo "📱 Available Android commands:"
        PS3="Select a command: "
        select opt in $CHOICES "Cancel"; do
            case $opt in
                "Cancel") break ;;
                *) [ -n "$opt" ] && just "$opt"; break ;;
            esac
        done
    fi
