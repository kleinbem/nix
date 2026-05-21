import 'common.just'

set working-directory := ".."

# --- Deployment ---

[group("Fleet")]
[confirm("🚀 Deploy configuration to the ENTIRE FLEET via Colmena?")]
deploy-fleet:
    @echo "🚀 Deploying to entire fleet via Colmena..."
    colmena apply --show-trace

[group("Fleet")]
deploy-orin:
    @echo "🟢 Deploying to Orin Nano..."
    colmena apply --on orin-nano

[group("Fleet")]
deploy-edge:
    @echo "📡 Deploying to AI Edge (Orin + Raspberry Pi)..."
    colmena apply --on orin-nano,core-pi,hass-pi

[group("Status")]
fleet mode="minimal":
    @echo "🚢 Container Fleet Status (Mode: {{mode}})"
    @ssh root@caddy.local "caddy list-adapters"
    @nix run nixpkgs#glances

[group("Development")]
dev-dashboard:
    @echo "📊 Launching Local Dashboard..."
    @HOMEPAGE_CONFIG_DIR=$(pwd)/.dev-dashboard XDG_CACHE_HOME=$(pwd)/.dev-dashboard/cache PORT=8083 nix run nixpkgs#homepage-dashboard

[group("Status")]
orin-ping:
    @ping -c 3 orin-nano.local

[group("Status")]
orin-status:
    @ssh root@orin-nano.local "tegrastats --interval 1000 | head -n 5"

[group("Debugging")]
orin-logs service="ollama":
    @ssh root@orin-nano.local "journalctl -u {{service}} -n 50 --no-pager"

[group("Debugging")]
orin-shell:
    @ssh root@orin-nano.local

[group("Provisioning")]
[confirm("💿 WIPE the Orin Nano and perform a fresh NixOS installation? This is destructive.")]
orin-install target="root@orin-nano.local":
    @echo "💿 Preparing Orin Nano for NixOS..."
    @nix run github:nix-community/disko -- --mode zap_create_mount ./hosts/orin-nano/disko.nix
    @nixos-install --flake .#orin-nano --target-host {{target}}

[group("Provisioning")]
[confirm("🔐 Seal the TPM key on the Orin Nano? This can only be done once after boot.")]
orin-seal:
    @echo "🔐 Sealing Orin Nano TPM keys..."
    @ssh root@orin-nano.local "tpm2_pcrseal -g sha256 -l 7 -o /persist/tpm-seal.bin"

[group("Provisioning")]
[confirm("💿 WIPE the USB SSD and install NixOS for Orin Nano? This is destructive.")]
orin-install-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "💿 Wiping and partitioning {{device}}..."
    sudo vgchange -an vg_orin || true
    disk_name=$(basename {{device}})
    if [ -d "/sys/class/block/$disk_name" ]; then
        for holder in /sys/class/block/$disk_name/*/holders/*; do
            if [ -e "$holder" ]; then
                dm_name=$(basename "$(readlink "$holder")")
                sudo cryptsetup close "$dm_name" || true
            fi
        done
    fi
    sudo nix run github:nix-community/disko -- --mode destroy,format,mount --argstr device {{device}} --arg secondDiskDevice null --root-mountpoint /mnt/orin ./nix-config/hosts/orin-nano/disko.nix
    echo "🏗️ Installing NixOS closure to {{device}} mounted at /mnt/orin..."
    sudo nixos-install --root /mnt/orin --flake .#orin-nano --no-root-passwd --option builders "" --option sandbox false
    echo "🔌 Cleaning up and unmounting..."
    sudo umount -R /mnt/orin || true
    sudo vgchange -an vg_orin || true
    sudo cryptsetup close orin_crypt || true
    echo "✅ Orin Nano SSD installation complete! You can now safely unplug it and insert it into the Jetson."


# --- Router LXC ---

[group("Router")]
deploy-router-lxc host="router-1":
    @echo "🏗️ Building LXC image for {{host}}..."
    nix build ".#{{host}}-image" --out-link result-{{host}}
    @echo "📦 Uploading to Router B (192.168.1.2)..."
    # nixos-generators LXC format produces a tarball in result/tarball/
    scp result-{{host}}/tarball/*.tar.xz root@192.168.1.2:/srv/lxc/nixos-{{host}}.tar.xz
    @echo "🚀 Activating container on router..."
    ssh root@192.168.1.2 "lxc-stop -n {{host}} || true; mkdir -p /srv/lxc/{{host}}/rootfs; tar -xf /srv/lxc/nixos-{{host}}.tar.xz -C /srv/lxc/{{host}}/rootfs; lxc-start -n {{host}}"
    @echo "✅ Deployment of {{host}} complete."

[group("Router")]
router-secrets file="site.yml":
    @echo "🔐 Editing OpenWrt secrets: {{file}}..."
    @cd ../openwrt/openwrt-secrets && sops {{file}}

[group("Router")]
router-provision:
    @echo "⚙️  Provisioning OpenWrt routers via Ansible..."
    @cd ../openwrt/openwrt-config && just provision
