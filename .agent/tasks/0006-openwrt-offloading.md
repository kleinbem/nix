---
status: backlog
priority: high
tags: [openwrt, architecture, offloading, infrastructure]
created: 2026-03-24
---
# 🧠 Mission: OpenWRT "Brain" Offloading (Banana Pi R4)

**Objective:** Fully leverage the Banana Pi R4's hardware (high-speed networking + NVMe storage) to offload infrastructure services from the NixOS AI workstation.

---

## 1. Governance & Security
- [ ] **Moving the Reverse Proxy (Caddy LXC):** Migrate the main SSL entry point from the PC to an LXC container on the router.
- [ ] **Step-CA (Internal PKI):** Establish the router as the Root CA for the entire lab.
- [ ] **Unified Authentication (Authelia):** Add an SSO layer on the router to protect all internal AI UIs.

## 2. Observability & Persistence
- [ ] **Loki Logging Hub:** Use the R4's NVMe SSD as the primary log aggregator.
- [ ] **Prometheus Metrics:** Centralize metrics collection on the router.
- [ ] **NetBox (IPAM):** Move the service inventory from a flat file to a live NetBox instance on the router.

## 3. Network Performance
- [ ] **ZRAM Optimization:** Configure large ZRAM on the R4 for smooth LXC operation.
- [ ] **DNS (Unbound/AdGuard):** Move local DNS resolution to the router for better caching.
- [ ] **Wireguard Mesh:** Use the router as the primary hub for the lab's secure transit.
