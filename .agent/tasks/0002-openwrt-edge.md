---
status: backlog
priority: medium
tags: [network, openwrt, dns, hardware]
created: 2026-03-24
---
# 🌐 Mission: OpenWRT "Gatekeeper" (Banana Pi R4 Hardware)

**Objective:** Configure dual Banana Pi R4 routers with OpenWRT to manage physical network entry, local DNS resolution, and **outsource edge complexity** (CA, SSL, Logs) from the AI host.

---

## 1. Hardware & OS (BPi R4)
- [ ] Flash latest OpenWRT Snapshot (or stable with MT7988 support).
- [ ] Establish basic WAN/LAN connectivity.
- [ ] Enable WiFi 7 (if compatible).

## 2. Infrastructure Outsourcing (Endgame)
- [ ] **Centralized PKI (Step-CA):** Deploy Step-CA or an internal CA on the router to manage certs for the whole lab.
- [ ] **Edge SSL Termination:** Router handles external HTTPS and passes cleaned traffic to the NixOS Gateway.
- [ ] **Log Aggregator (Loki):** Move Loki/Promtail logic to the router to free up PC RAM.
- [ ] **Tailscale:** Install and authenticate; enable **Subnet Router** and **Exit Node**.

## 3. LAN Coordination & DNS
- [ ] **DNSmasq/Unbound:** Configure local DNS to resolve `*.local` to the Gateway.
- [ ] **Firewall:** Configure nftables to block all traffic to `10.85.46.0/24` except via Proxy.
- [ ] Set **Static IP Lease** for the NixOS Workstation.
- [ ] Configure Link Aggregation (if using multiple Ethernet ports).
