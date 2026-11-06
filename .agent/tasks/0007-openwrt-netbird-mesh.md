---
status: backlog
priority: high
tags: [network, openwrt, netbird, mesh, security]
created: 2026-03-25
---
# 🦅 Mission: NetBird Mesh Networking (Gatekeeper Node)

**Objective:** Implement a secure, peer-to-peer NetBird mesh across all lab nodes, using the Banana Pi R4 (`router-1`) as the primary routing hub and stable entry point.

---

## 1. Gateway Deployment (BPi R4)
- [ ] **Declarative Install:** Enable `services.netbird.enable = true;` in `hosts/router-1/default.nix`.
- [ ] **Authentication:** Authenticate the router node to the NetBird Control Plane (using Setup Key).
- [ ] **Subnet Routing:** Configure the router as a **Routing Peer** in the NetBird dashboard to advertise the local LAN (`192.168.1.0/24`).
- [ ] **Firewall Tuning:** Ensure `nftables` / `fw4` allow traffic on the NetBird interface (`wt0`).

## 2. Global Mesh Integration
- [ ] **Edge Nodes:** Add the Orin Nano and Raspberry Pi 5 nodes to the mesh.
- [ ] **Mobile/Remote Access:** Join external devices (laptop/mobile) to the mesh for remote management.
- [ ] **DNS Integration:** Configure NetBird's **MagicDNS** to resolve lab hostnames (e.g., `workstation.netbird.cloud`).

## 3. Security & Optimization
- [ ] **Access Control (ACLs):** Restrict mesh traffic so only specific peers can access the AI UIs (ComfyUI, Langflow).
- [ ] **Performance Benchmarking:** Verify that the WireGuard backplane handles 1Gbps+ throughput on the BPi R4.
- [ ] **Failover:** (Optional) Configure `router-2` as a secondary routing peer for high availability.
