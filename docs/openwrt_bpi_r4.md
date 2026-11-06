# Banana Pi R4 (OpenWrt) Integration Guide

This document outlines the steps to integrate your BPI-R4 router as the primary Service Discovery and Gateway layer for your NixOS fleet.

## 1. Network Topology
- **Host Bridge**: `10.85.46.1` (Your NixOS Workstation)
- **BPI-R4 IP**: `10.85.46.2` (Recommended)
- **Subnet**: `10.85.46.0/24`

## 2. Service Discovery (DNS)
To enable `.local` resolution across your fleet:
1. **AdGuard Home / Dnsmasq**:
   - Add a custom DNS rewrite: `*.local` -> `10.85.46.107` (Caddy Proxy).
   - This ensures all your services (e.g., `authelia.local`, `grafana.local`) resolve to your reverse proxy.

## 3. WireGuard / Tailscale Exit Node
- Install `tailscale` or use the OpenWrt WireGuard package.
- Configure the BPI-R4 as a **Subnet Router** for `10.85.46.0/24`.
- This allows you to access your AI agents and dashboard from anywhere securely.

## 4. VLAN Isolation (The AI Airlock)
- Create a dedicated VLAN for ports connected to your AI inference nodes.
- Use OpenWrt's firewall to restrict this VLAN to **Local DNS** and **WAN HTTPS** only.
- This creates a hardware-level "Airlock" that mirrors the NixOS Zero-Trust policy.

## 5. Port Forwarding
If you need external access (not recommended, use VPN instead):
- Forward `:443` -> `10.85.46.107:443` (Caddy).
- **Security Warning**: Ensure Authelia is active on all endpoints before doing this.

---
*Status: Pending Activation of BPI-R4.*
