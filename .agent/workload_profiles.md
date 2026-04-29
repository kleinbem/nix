# Workload Profile Matrix

This document tracks the status of system services across different NixOS Specialisations (modes).

## Service Availability Matrix

| Service / Capability | Default | Playground | Work | Waydroid | Work-Waydroid | Play-Waydroid | Hardened |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **n8n** | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **code-server** | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **open-webui** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **dashboard** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **qdrant** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **litellm** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **playground (AI)** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **caddy (Proxy)** | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **comfyui** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **langflow** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **langfuse** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **agent-team** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **ollama (Native)** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **android-emulator** | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **waydroid** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| **nix-mineral** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Printing** | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Avahi Discovery** | ✅ | ✅ | ✅ | ✅ | ❌ |

## Legend
- ✅ **Enabled**: Service is active and reachable.
- ❌ **Disabled**: Service is completely turned off to save resources.

## Usage Guide

### Switching Modes
Use the `just` commands to switch between profiles live:

```bash
just modes           # List all modes
just mode playground # Switch to full AI suite
just mode work       # Switch to productivity mode
just mode minimal    # Switch to core system only
just reset-mode      # Alias for minimal/base config
```

### Persistent Selection
If you want to boot into a specific mode, select it from the systemd-boot menu during startup.

---
*Last Updated: April 2026*
