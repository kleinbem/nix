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

[group("Provisioning")]
[confirm("💿 Re-install full orin-nano config onto the bootstrapped Orin? Builds natively on the device (no cross-compilation). This reformats the SSD.")]
[doc("Requires bootstrap running, SSH key working, and LUKS passphrase ready. Builds the full aarch64 closure on the Orin then reformats disk with LUKS+LVM+impermanence layout.")]
orin-promote host="root@orin-nano-bootstrap.local":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔑 Enter the LUKS passphrase for the new orin-nano install:"
    read -s -r LUKS_KEY
    echo "🔨 Building and installing full orin-nano config (native aarch64 build on the Orin)..."
    # nixos-anywhere: --build-on-remote avoids x86_64 → aarch64 cross-compilation.
    # The generated LUKS passphrase is only for initial setup; seal TPM2 afterwards with: just orin-seal
    echo "$LUKS_KEY" | nix run github:nix-community/nixos-anywhere -- \
        --flake ./nix-config#orin-nano \
        --build-on-remote \
        --disk-encryption-keys /dev/stdin - \
        {{host}}
    echo "✅ Full orin-nano installed! Now seal TPM2 with: just orin-seal"

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
[confirm("🟢 Install minimal NixOS bootstrap onto USB SSD for Orin Nano? This is destructive.")]
orin-install-bootstrap device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "💿 Wiping {{device}} for bootstrap install..."
    sudo vgchange -an vg_orin || true
    disk_name=$(basename {{device}})
    for part in /sys/class/block/${disk_name}*/holders/*; do
        [ -e "$part" ] && sudo cryptsetup close "$(basename "$(readlink "$part")")" 2>/dev/null || true
    done
    sudo dd if=/dev/zero of={{device}} bs=1M count=1200 status=none
    echo "🗂️  Partitioning and formatting via disko..."
    sudo nix run github:nix-community/disko -- --mode destroy,format,mount --argstr device {{device}} --root-mountpoint /mnt/orin-bootstrap ./nix-config/hosts/orin-nano-bootstrap/disko.nix
    echo "🏗️  Installing bootstrap NixOS closure..."
    sudo nixos-install --root /mnt/orin-bootstrap --flake ./nix-config#orin-nano-bootstrap --no-root-passwd --option builders ""
    echo "🔌 Cleaning up..."
    sudo umount -R /mnt/orin-bootstrap || true
    echo "✅ Bootstrap done! Plug the SSD into the Orin, boot it, then SSH in and run: just deploy-orin-self"

[group("Provisioning")]
[confirm("💿 WIPE the USB SSD and install NixOS for Orin Nano? This is destructive.")]
orin-install-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "💿 Wiping and partitioning {{device}}..."
    sudo vgchange -an vg_orin || true
    # Close any open dm devices backed by this disk (partitions included)
    disk_name=$(basename {{device}})
    for part in /sys/class/block/${disk_name}*/holders/*; do
        [ -e "$part" ] && sudo cryptsetup close "$(basename "$(readlink "$part")")" 2>/dev/null || true
    done
    # Wipe first 1200M: clears GPT, the 1G ESP, and the LUKS header at the start of partition 2
    sudo dd if=/dev/zero of={{device}} bs=1M count=1200 status=none
    sudo nix run github:nix-community/disko -- --mode destroy,format,mount --argstr device {{device}} --arg secondDiskDevice null --root-mountpoint /mnt/orin ./nix-config/hosts/orin-nano/disko.nix
    echo "🏗️ Installing NixOS closure to {{device}} mounted at /mnt/orin..."
    sudo nixos-install --root /mnt/orin --flake ./nix-config#orin-nano --no-root-passwd --option builders ""
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
