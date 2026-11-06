---
status: backlog
priority: high
tags: [nix, networking, edge, security]
created: 2026-03-24
---
# ❄️ Mission: NixOS Edge Integration (Bridge to OpenWRT)

**Objective:** Adjust the NixOS Workstation network configuration to work seamlessly with the new OpenWRT routers, ensuring stable interface bindings and firewall rules.

---

## 1. Network Permanence
- [ ] **Interface Naming:** Ensure the primary Ethernet interface is predictably named or matched by MAC.
- [ ] **Static Configuration:** Configure `networking.interfaces` to expect the static IP assigned by OpenWRT.
- [ ] **Bridge Binding:** Verify the `cbr0` bridge correctly routes through the primary LAN interface.

## 2. Security Alignment
- [ ] **Host Firewall:** Update `networking.firewall.allowedTCPPorts` to only trust traffic from the OpenWRT LAN IP.
- [ ] **Caddy Binding:** Ensure Caddy is listening on the Bridge IP and that it's reachable from the main LAN.

## 3. Monitoring & Health
- [ ] **Exporter:** Set up `prometheus-node-exporter` on NixOS to be scraped by the (future) Monitoring container.
- [ ] **DNS Verification:** Test that `*.local` resolution works from the host via the OpenWRT upstream.

---

## 📋 Execution Checklist
- [ ] Update `inventory.nix` with any new network topology changes.
- [ ] Rebuild and switch NixOS configuration.
- [ ] Stress-test mTLS proxy access from "external" LAN devices (via OpenWRT).
