#!/usr/bin/env bash
# waydroid-fix-and-start.sh
set -e

echo "--- Stopping all processes ---"
waydroid session stop || true
sudo systemctl stop waydroid-container || true
sudo pkill -9 lxc-start || true

echo "--- Ensuring Network Bridge (waydroid0) ---"
sudo ip link delete waydroid0 &>/dev/null || true
sudo ip link add name waydroid0 type bridge
sudo ip addr add 192.168.240.1/24 dev waydroid0
sudo ip link set waydroid0 up
echo "Bridge [waydroid0] initialized."

echo "--- Creating Network Mock (Fixes NixOS Crash) ---"
# Create a dummy script that always succeeds
echo '#!/bin/sh' > /tmp/waydroid-net-mock.sh
echo 'exit 0' >> /tmp/waydroid-net-mock.sh
chmod +x /tmp/waydroid-net-mock.sh

# Find the real script path in the nix store
REAL_NET_SCRIPT=$(find /nix/store -maxdepth 4 -name "waydroid-net.sh" | grep -v ".drv" | head -n 1)

echo "--- Rebuilding LXC Config ---"
sudo tee /var/lib/waydroid/lxc/waydroid/config <<EOF
# Waydroid LXC Config
lxc.rootfs.path = /var/lib/waydroid/rootfs
lxc.arch = x86_64
lxc.autodev = 0
lxc.uts.name = waydroid
lxc.console.path = none
lxc.init.cmd = /init
lxc.mount.auto = cgroup:ro sys:ro proc

# Critical NixOS Hardware/Security Fixes
lxc.apparmor.profile = unconfined
lxc.no_new_privs = 0
lxc.cap.drop =
lxc.cgroup2.devices.allow = c *:* rwm

# Mock the failing network script
lxc.mount.entry = /tmp/waydroid-net-mock.sh ${REAL_NET_SCRIPT#/} none bind,ro 0 0

# Essential includes
lxc.include = /var/lib/waydroid/lxc/waydroid/config_nodes
lxc.include = /var/lib/waydroid/lxc/waydroid/config_session

# Networking
lxc.net.0.type = veth
lxc.net.0.flags = up
lxc.net.0.link = waydroid0
lxc.net.0.name = eth0
lxc.net.0.hwaddr = 00:16:3e:00:00:01

lxc.pty.max = 10
lxc.seccomp.allow_nesting = 1
EOF

echo "--- Starting Container Service ---"
sudo systemctl start waydroid-container
sleep 3

echo "--- Verifying Container Pulse ---"
if sudo waydroid shell ls /data/ >/dev/null 2>&1; then
    echo "SUCCESS: Container is ALIVE!"
    echo "--- Starting UI Session ---"
    waydroid session start &
    sleep 5
    waydroid show-full-ui
else
    echo "Container stalling. Forcing manual start..."
    sudo waydroid container start || true
    sleep 5
    if sudo waydroid shell ls /data/ >/dev/null 2>&1; then
        echo "SUCCESS: Container is ALIVE (after manual trigger)!"
        waydroid session start &
        sleep 5
        waydroid show-full-ui
    else
        echo "ERROR: Container is still stalling."
        sudo waydroid log | tail -n 10
    fi
fi
