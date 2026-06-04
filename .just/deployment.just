import 'common.just'

set working-directory := ".."

# --- Deployment ---

[group("Fleet")]
[confirm("🚀 Deploy configuration to the ENTIRE FLEET via Colmena?")]
deploy-fleet:
    @echo "🚀 Deploying to entire fleet via Colmena..."
    colmena -f ./nix-config/flake.nix apply --impure --show-trace

[group("Fleet")]
deploy-orin:
    @echo "🟢 Deploying to Orin Nano..."
    colmena -f ./nix-config/flake.nix apply --impure --on orin-nano

[group("Provisioning")]
[confirm("💿 Re-install full orin-nano config onto the bootstrapped Orin? Builds natively on the device (no cross-compilation). This reformats the SSD.")]
[doc("Requires bootstrap running and SSH key working. Builds aarch64 closure on the Orin itself, reformats disk with full LUKS+LVM+impermanence layout. LUKS passphrase is prompted interactively. Seal TPM2 afterwards with: just deployment::orin-seal")]
orin-promote host="root@orin-nano-bootstrap.local":
    @echo "🔨 Building and installing full orin-nano config (native aarch64 build on the Orin)..."
    @echo "   LUKS passphrase will be prompted interactively. Seal TPM2 afterwards with: just deployment::orin-seal"
    nix run github:nix-community/nixos-anywhere -- \
        --flake ./nix-config#orin-nano \
        --build-on-remote \
        --phases kexec,disko,install,reboot \
        {{host}}

[group("Provisioning")]
[confirm("💿 Install full orin-nano config skipping kexec? Use this when kexec fails (e.g. Jetson). Target must be reachable and disk not in active use.")]
orin-promote-nokexec host="root@orin-nano-bootstrap.local":
    @echo "🔨 Building and installing full orin-nano config (no kexec — skips RAM boot)..."
    nix run github:nix-community/nixos-anywhere -- \
        --flake ./nix-config#orin-nano \
        --build-on-remote \
        --phases disko,install,reboot \
        {{host}}

[group("Fleet")]
deploy-edge:
    @echo "📡 Deploying to AI Edge (Orin + Raspberry Pi)..."
    colmena -f ./nix-config/flake.nix apply --impure --on orin-nano,core-pi,hass-pi

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
[confirm("🔐 Seal the TPM key on the Orin Nano? This can only be done once after boot.")]
orin-seal:
    @echo "🔐 Sealing Orin Nano TPM keys..."
    @ssh root@orin-nano.local "tpm2_pcrseal -g sha256 -l 7 -o /persist/tpm-seal.bin"

[group("Provisioning")]
[confirm("🟢 Install minimal NixOS bootstrap onto USB SSD for Orin Nano? This is destructive.")]
orin-install-bootstrap device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Ensuring clean state before install..."
    sudo umount -R /mnt/orin-bootstrap 2>/dev/null || true
    sudo vgchange -an vg_orin 2>/dev/null || true
    disk_name=$(basename {{device}})
    for part in /sys/class/block/${disk_name}*/holders/*; do
        [ -e "$part" ] && sudo cryptsetup close "$(basename "$(readlink "$part")")" 2>/dev/null || true
    done
    sudo cryptsetup close orin_crypt 2>/dev/null || true
    echo "💿 Wiping {{device}}..."
    sudo dd if=/dev/zero of={{device}} bs=1M count=1200 status=none
    sudo wipefs -a {{device}} 2>/dev/null || true
    for part in $(ls {{device}}* 2>/dev/null | grep -v "^{{device}}$"); do
        sudo wipefs -a "$part" 2>/dev/null || true
    done
    sudo partprobe {{device}} 2>/dev/null || true
    echo "🗂️  Partitioning and formatting via disko..."
    sudo nix run github:nix-community/disko -- --mode destroy,format,mount --argstr device {{device}} --root-mountpoint /mnt/orin-bootstrap ./nix-config/hosts/orin-nano-bootstrap/disko.nix
    echo "🔨 Building aarch64 closure (sandbox disabled for QEMU JIT, skipping offline remote builder)..."
    # nixos-install does not forward --option to its internal nix build, so we pre-build here
    # where sandbox=false and builders="" are honoured, then hand the result to --system.
    nix build ./nix-config#nixosConfigurations.orin-nano-bootstrap.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        {{OVERRIDES}} \
        --out-link /tmp/orin-bootstrap-system
    echo "🏗️  Installing bootstrap NixOS closure (skipping bootloader — installed manually below)..."
    # --no-bootloader: nixos-install's bootloader step chroots into aarch64 binaries via QEMU,
    # but QEMU's uname() returns x86_64, causing bootctl to bail with exit 255.
    # All bootloader files are just static copies; we do them from the host side instead.
    sudo nixos-install --root /mnt/orin-bootstrap --system "$(readlink /tmp/orin-bootstrap-system)" --no-root-passwd --no-bootloader

    echo "💾 Installing systemd-boot to ESP (host-side, no aarch64 execution required)..."
    SYSTEM="$(readlink /tmp/orin-bootstrap-system)"
    ESP="/mnt/orin-bootstrap/boot"

    BOOT_EFI="$(find /mnt/orin-bootstrap/nix/store -maxdepth 6 -name "systemd-bootaa64.efi" 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootaa64.efi not found in store" >&2; exit 1; }

    KERNEL_SRC="$(realpath "${SYSTEM}/kernel")"
    INITRD_SRC="$(realpath "${SYSTEM}/initrd")"
    KERNEL_PARAMS="$(cat "${SYSTEM}/kernel-params")"
    SYS_STORE_PATH="/nix/store/$(basename "${SYSTEM}")"

    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootaa64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTAA64.EFI"
    sudo cp "${KERNEL_SRC}" "${ESP}/EFI/nixos/kernel"
    sudo cp "${INITRD_SRC}" "${ESP}/EFI/nixos/initrd"

    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null

    ENTRY="$(mktemp)"
    printf 'title NixOS Bootstrap\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "${SYS_STORE_PATH}" "${KERNEL_PARAMS}" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"
    rm "${ENTRY}"

    rm -f /tmp/orin-bootstrap-system
    echo "🔌 Cleaning up..."
    sudo umount -R /mnt/orin-bootstrap || true
    echo "✅ Bootstrap done! Plug the SSD into the Orin, boot it, then run: just deployment::orin-promote"

[group("Provisioning")]
[confirm("💿 WIPE the USB SSD and install NixOS for Orin Nano? This is destructive.")]
orin-install-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail

    _cleanup_dm() {
        # Deactivate LVM VG, close any LUKS mapped from partitions of this disk, then
        # force-remove residual device-mapper entries.  A lingering orin_crypt (from a
        # previous failed run) causes disko to skip luksOpen and pvcreate to see stale
        # LVM signatures; a 0-sector orin_crypt left after a --persistent dm-table
        # reload causes pvcreate to report "device is not in a usable state".
        # Tear down strictly top-down: unmount -> remove LV dm devices -> close LUKS.
        # A previous run can leave vg_orin LVs *active and mounted* on top of orin_crypt
        # while a later pvcreate has already overwritten the on-disk PV metadata.  In
        # that state `vgchange -an`/`vgremove` are no-ops (LVM no longer recognises the
        # VG), yet the kernel dm devices and the /dev/vg_orin node persist and block the
        # next vgcreate with "/dev/vg_orin already exists in filesystem".
        # A real (non-lazy) unmount is required: lazy unmount leaves the LVs held open,
        # so dmsetup only defers removal and /dev/vg_orin stays alive.  A plain
        # `umount -R` fails "busy" when a stray process (or a half-finished installer)
        # still has the LV open, so kill holders with fuser before unmounting each
        # mountpoint, deepest first.
        for mp in $(awk '$2 ~ "^/mnt/orin" {print $2}' /proc/mounts | sort -r); do
            sudo fuser -km "$mp" 2>/dev/null || true
            sudo umount "$mp" 2>/dev/null || sudo umount -l "$mp" 2>/dev/null || true
        done
        sudo sync
        sudo vgchange -an vg_orin 2>/dev/null || true
        # Force-remove every vg_orin LV dm device (works even when LVM has lost the VG)
        for dm in $(sudo dmsetup ls 2>/dev/null | awk '{print $1}' | grep -E '^vg_orin'); do
            sudo dmsetup remove -f --retry "$dm" 2>/dev/null || true
        done
        sudo vgremove -f vg_orin 2>/dev/null || true
        # Nothing sits on orin_crypt now — close the LUKS container and any crypt on this disk
        local disk_name
        disk_name=$(basename {{device}})
        for part in /sys/class/block/${disk_name}*/holders/*; do
            [ -e "$part" ] && sudo cryptsetup close "$(basename "$(readlink "$part")")" 2>/dev/null || true
        done
        sudo cryptsetup close orin_crypt 2>/dev/null || true
        sudo dmsetup remove -f --retry orin_crypt 2>/dev/null || true
        # Remove LVM backup/archive so udev can't auto-restore vg_orin after pvcreate
        sudo rm -f /etc/lvm/backup/vg_orin 2>/dev/null || true
        sudo rm -f /etc/lvm/archive/vg_orin_*.vg 2>/dev/null || true
        # Remove stale /dev/vg_orin node (left when LVs were force-removed while mounted)
        sudo rm -rf /dev/vg_orin 2>/dev/null || true
        sudo udevadm settle 2>/dev/null || true
    }

    _wipe_disk() {
        # Wipe first 1200 MiB: clears GPT, the 1 GiB ESP, and the LUKS header at the
        # start of partition 2.  Avoid wiping individual partition nodes — the kernel
        # may already have removed them after the GPT was zeroed, and running wipefs on
        # stale sdb1/sdb2 nodes can confuse the USB controller's partition-size cache.
        echo "💿 Wiping {{device}}..."
        sudo dd if=/dev/zero of={{device}} bs=1M count=1200 status=none
        sudo sync
        sudo wipefs -a {{device}} 2>/dev/null || true
        sudo blockdev --rereadpt {{device}} 2>/dev/null || sudo partprobe {{device}} 2>/dev/null || true
        sudo udevadm settle 2>/dev/null || true
    }

    _run_disko() {
        sudo nix run github:nix-community/disko -- \
            --mode destroy,format,mount \
            --argstr device {{device}} \
            --arg secondDiskDevice null \
            --root-mountpoint /mnt/orin \
            ./nix-config/hosts/orin-nano/disko.nix
    }

    echo "🔍 Ensuring clean state before install..."
    _cleanup_dm
    _wipe_disk

    # disko can fail on USB-NVMe enclosures in two recoverable ways:
    #   1. 0-sector dm-crypt: disko's luksOpen uses --allow-discards --persistent,
    #      which writes back to the raw LUKS header.  On UAS enclosures this can
    #      trigger a command abort that momentarily presents orin_crypt with 0
    #      sectors, so pvcreate fails with "device is not in a usable state".
    #   2. Stale /dev/vg_orin node: udev leaves the directory node behind from a
    #      prior attempt's brief auto-activation.  LVM has no such VG (vgdisplay
    #      fails), yet vgcreate refuses because the /dev node already exists.
    # Both are fixed by a clean wipe + one full retry — no reboot required.
    if ! _run_disko; then
        crypt_size=$(sudo blockdev --getsize64 /dev/mapper/orin_crypt 2>/dev/null || echo 0)
        if [ "$crypt_size" = "0" ]; then
            echo "🔄 disko failed: 0-sector dm-crypt device (USB re-enumeration race)."
        elif [ -d /dev/vg_orin ] && ! sudo vgdisplay vg_orin >/dev/null 2>&1; then
            echo "🔄 disko failed: stale /dev/vg_orin node with no backing VG (udev leftover)."
        else
            echo "❌ disko failed for an unrecognized reason (orin_crypt size: ${crypt_size}).  Aborting."
            exit 1
        fi
        echo "🔄 Retrying full disko install from scratch..."
        _cleanup_dm
        _wipe_disk
        if ! _run_disko; then
            echo "❌ disko failed again after recovery — manual intervention needed."
            echo "   Try: sudo cryptsetup close orin_crypt; sudo rm -rf /dev/vg_orin; sudo udevadm settle"
            exit 1
        fi
    fi

    _setup_host_identity() {
        # Generates SSH host keys and the sops age key into the persist volume while
        # the SSD is still mounted, then wires the public age key into .sops.yaml and
        # re-encrypts secrets.  This means the first boot has all secrets available
        # without any post-boot manual steps.
        local persist="/mnt/orin/nix/persist"
        echo "🔑 Setting up host identity..."

        sudo mkdir -p "${persist}/etc/ssh" "${persist}/var/lib/sops/age"
        sudo chmod 700 "${persist}/var/lib/sops/age"

        # Generate persistent SSH host keys (stored in /nix/persist via impermanence)
        if [ ! -f "${persist}/etc/ssh/ssh_host_ed25519_key" ]; then
            sudo ssh-keygen -t ed25519 -f "${persist}/etc/ssh/ssh_host_ed25519_key" -N "" -C "orin-nano" -q
            sudo ssh-keygen -t rsa -b 4096 -f "${persist}/etc/ssh/ssh_host_rsa_key" -N "" -C "orin-nano" -q
            sudo chmod 600 "${persist}/etc/ssh/ssh_host_ed25519_key" "${persist}/etc/ssh/ssh_host_rsa_key"
            sudo chmod 644 "${persist}/etc/ssh/ssh_host_ed25519_key.pub" "${persist}/etc/ssh/ssh_host_rsa_key.pub"
        fi

        # Derive age keys from the SSH ed25519 host key.
        # Run ssh-to-age as the current user (it reads from stdin to avoid sudo PATH issues).
        local age_pubkey
        age_pubkey=$(sudo cat "${persist}/etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age)
        sudo cat "${persist}/etc/ssh/ssh_host_ed25519_key" \
            | ssh-to-age --private-key \
            | sudo tee "${persist}/var/lib/sops/age/host.txt" > /dev/null
        sudo chmod 600 "${persist}/var/lib/sops/age/host.txt"

        # Stable machine-id for journald / systemd (persisted via impermanence)
        if [ ! -f "${persist}/etc/machine-id" ]; then
            systemd-id128 new | sudo tee "${persist}/etc/machine-id" > /dev/null
            sudo chmod 444 "${persist}/etc/machine-id"
        fi

        echo "📋 orin-nano age public key: ${age_pubkey}"

        # Add the age public key to .sops.yaml and re-encrypt secrets so that
        # the Orin can decrypt them on first boot without any further intervention.
        local sops_yaml="./nix-secrets/.sops.yaml"
        if grep -qF "${age_pubkey}" "${sops_yaml}"; then
            echo "   Age key already in .sops.yaml — skipping re-encryption."
            return
        fi

        # Insert after the last age key line using awk (preserves comments)
        awk -v key="${age_pubkey}" '
            /^[[:space:]]*- "age1/ { last = NR }
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    print lines[i]
                    if (i == last) {
                        print "          # Host Key (orin-nano)"
                        print "          - \"" key "\""
                    }
                }
            }
        ' "${sops_yaml}" > /tmp/sops_updated.yaml && mv /tmp/sops_updated.yaml "${sops_yaml}"

        echo "🔐 Re-encrypting secrets (YubiKey touch may be required)..."
        # Run from inside nix-secrets: sops resolves .sops.yaml relative to the CWD,
        # so invoking it from the repo root fails with "config file not found".
        ( cd ./nix-secrets && sops updatekeys --yes secrets.yaml )
        echo "✅ Secrets updated."
        echo ""
        echo "   Commit nix-secrets + nix-config before deploying:"
        echo "   just git::save 'feat: add orin-nano host key and re-encrypt secrets'"
    }

    echo "🏗️ Installing NixOS closure to {{device}} mounted at /mnt/orin..."
    nix build ./nix-config#nixosConfigurations.orin-nano.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        {{OVERRIDES}} \
        --out-link /tmp/orin-system
    # --no-bootloader: nixos-install's bootloader step chroots into aarch64 binaries via
    # QEMU, but QEMU's uname() returns x86_64, so bootctl bails with exit 255.  The ESP
    # files are static copies, installed host-side below (mirrors orin-install-bootstrap).
    sudo nixos-install --root /mnt/orin --system "$(readlink /tmp/orin-system)" --no-root-passwd --no-bootloader

    echo "💾 Installing systemd-boot to ESP (host-side, no aarch64 execution required)..."
    SYSTEM="$(readlink /tmp/orin-system)"
    ESP="/mnt/orin/boot"

    BOOT_EFI="$(find /mnt/orin/nix/store -maxdepth 6 -name "systemd-bootaa64.efi" 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootaa64.efi not found in store" >&2; exit 1; }

    KERNEL_SRC="$(realpath "${SYSTEM}/kernel")"
    INITRD_SRC="$(realpath "${SYSTEM}/initrd")"
    KERNEL_PARAMS="$(cat "${SYSTEM}/kernel-params")"
    SYS_STORE_PATH="/nix/store/$(basename "${SYSTEM}")"

    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootaa64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTAA64.EFI"
    sudo cp "${KERNEL_SRC}" "${ESP}/EFI/nixos/kernel"
    sudo cp "${INITRD_SRC}" "${ESP}/EFI/nixos/initrd"

    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null

    ENTRY="$(mktemp)"
    printf 'title NixOS\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "${SYS_STORE_PATH}" "${KERNEL_PARAMS}" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"
    rm "${ENTRY}"

    rm -f /tmp/orin-system

    _setup_host_identity

    echo "🔌 Cleaning up and unmounting..."
    sudo umount -R /mnt/orin || true
    sudo vgchange -an vg_orin || true
    sudo cryptsetup close orin_crypt || true
    echo ""
    echo "✅ Orin Nano SSD installation complete!"
    echo "   Next steps:"
    echo "   1. Commit: just git::save 'feat: orin-nano install'"
    echo "   2. Plug SSD into the Jetson and boot"
    echo "   3. Deploy config: just deployment::deploy-orin"
    echo "   4. Seal TPM2: just deployment::orin-seal"


[group("Provisioning")]
[confirm("🔄 Re-install orin-nano config to an ALREADY-PROVISIONED SSD in the USB reader (NO wipe)? Mounts the existing LUKS/LVM, rebuilds, and refreshes the closure + bootloader.")]
[doc("Non-destructive in-place update of an installed Orin SSD. Mounts the existing disk via disko (prompts for the LUKS passphrase), rebuilds the closure with local overrides, reinstalls it, and re-writes systemd-boot host-side. Use after config changes (e.g. clevis/disko tweaks) without re-wiping or re-copying from scratch.")]
orin-update-usb device="/dev/sdb":
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🔓 Mounting existing SSD via disko (enter the Orin LUKS passphrase when prompted)..."
    sudo nix run github:nix-community/disko -- \
        --mode mount \
        --argstr device {{device}} \
        --arg secondDiskDevice null \
        --root-mountpoint /mnt/orin \
        ./nix-config/hosts/orin-nano/disko.nix

    echo "🏗️ Building orin-nano closure..."
    nix build ./nix-config#nixosConfigurations.orin-nano.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        {{OVERRIDES}} \
        --out-link /tmp/orin-system

    SYSTEM="$(readlink /tmp/orin-system)"
    ESP="/mnt/orin/boot"

    echo "💿 Installing closure (skipping bootloader — done host-side below)..."
    sudo nixos-install --root /mnt/orin --system "${SYSTEM}" --no-root-passwd --no-bootloader

    echo "💾 Installing systemd-boot to ESP (host-side, no aarch64 execution)..."
    BOOT_EFI="$(find /mnt/orin/nix/store -maxdepth 6 -name "systemd-bootaa64.efi" 2>/dev/null | head -1)"
    [ -n "$BOOT_EFI" ] || { echo "❌ systemd-bootaa64.efi not found in store" >&2; exit 1; }
    sudo mkdir -p "${ESP}/EFI/systemd" "${ESP}/EFI/BOOT" "${ESP}/EFI/nixos" "${ESP}/loader/entries"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/systemd/systemd-bootaa64.efi"
    sudo cp "${BOOT_EFI}" "${ESP}/EFI/BOOT/BOOTAA64.EFI"
    sudo cp "$(realpath "${SYSTEM}/kernel")" "${ESP}/EFI/nixos/kernel"
    sudo cp "$(realpath "${SYSTEM}/initrd")" "${ESP}/EFI/nixos/initrd"
    printf 'timeout 5\ndefault nixos-1.conf\neditor no\n' | sudo tee "${ESP}/loader/loader.conf" > /dev/null
    ENTRY="$(mktemp)"
    printf 'title NixOS\nlinux /EFI/nixos/kernel\ninitrd /EFI/nixos/initrd\noptions init=%s/init %s\n' \
        "/nix/store/$(basename "${SYSTEM}")" "$(cat "${SYSTEM}/kernel-params")" > "${ENTRY}"
    sudo cp "${ENTRY}" "${ESP}/loader/entries/nixos-1.conf"
    rm "${ENTRY}"
    rm -f /tmp/orin-system

    echo "🔌 Unmounting..."
    sudo umount -R /mnt/orin || true
    sudo vgchange -an vg_orin || true
    sudo cryptsetup close orin_crypt || true
    echo "✅ In-place update complete — put the SSD in the Orin, plug in ethernet, and boot."


[group("Provisioning")]
[confirm("🔄 Re-install core-pi config to an ALREADY-PROVISIONED SSD in the USB reader (NO wipe)?")]
[doc("Non-destructive in-place update of an installed core-pi SSD. Mounts the existing disk via disko, rebuilds the closure, and reinstalls it.")]
core-update-usb device="/dev/sdc":
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🔓 Mounting existing SSD via disko (enter the Pi LUKS passphrase when prompted)..."
    sudo nix run github:nix-community/disko -- \
        --mode mount \
        --argstr device {{device}} \
        --root-mountpoint /mnt/core-pi \
        ./nix-config/hosts/core-pi/disko.nix

    echo "🏗️ Building core-pi closure..."
    nix build ./nix-config#nixosConfigurations.core-pi.config.system.build.toplevel \
        --option sandbox false \
        --option builders "" \
        --out-link /tmp/core-pi-system

    SYSTEM="$(readlink /tmp/core-pi-system)"

    echo "💿 Installing closure..."
    sudo nixos-install --root /mnt/core-pi --system "${SYSTEM}" --no-root-passwd

    rm -f /tmp/core-pi-system

    echo "🔌 Unmounting..."
    sudo umount -R /mnt/core-pi || true
    sudo cryptsetup close core_crypt || true
    echo "✅ In-place update complete — put the SSD in the Pi and boot."


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

# --- Cloudflare ---

[group("Cloudflare")]
[doc("Deploy Cloudflare Tunnel and wildcard CNAME records via OpenTofu")]
cf-apply:
    @./scripts/tf-apply.sh
