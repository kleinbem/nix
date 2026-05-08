# Repository Map & Navigation Guide

This document serves as a map for understanding the structure of this Nix configuration repository. Use it to locate files or decide where to add new configuration.

## 📂 Root Directory

- **`flake.nix`**: The entry point for the entire configuration. Defines inputs (nixpkgs, home-manager, etc.) and outputs (nixosConfigurations).
- **`Justfile`**: Task runner for common operations. See built-in workflows for usage.
- **`flake.lock`**: Pinned versions of dependencies. Manage via `just update`.

## 🖥️ Hosts (`hosts/`)

Contains machine-specific configurations. Each folder represents a distinct host.

- **`nixos-nvme/`**: Main workstation configuration.
  - `configuration.nix`: System-level host config.
  - `home.nix`: Home Manager config for the main user (`martin`).
- **`jetson-orin/`**, **`pi5/`**, **`qnap/`**: Configurations for other devices.

## 🧩 Modules (`modules/`)

Reusable configuration blocks shared across hosts.

- **`nixos/`**: System-level modules (e.g., `core.nix`, `virtualisation.nix`, `security.nix`).
  - *Rule*: Import these in `configuration.nix`.
- **`home-manager/`**: User-level modules (e.g., shell configs, git, editors).
  - *Rule*: Import these in `home.nix`.

## 🧠 Context (`.agent/context/`)

Documentation and rules for the repository.

- **`constitution.md`**: Core rules for maintaining purity and structure.
- **`system-architecture.md`**: High-level overview of the hardware and software stack.
- **`repository-map.md`**: This file.

## 🤖 Automations (`.agent/`)

- **`workflows/`**: Step-by-step guides for AI agents to perform tasks (e.g., testing, deploying).

---

## 🧭 Navigation Heuristics

- **Adding a System Service**: Check `modules/nixos/` first. If generic, add there. If host-specific, add to `hosts/<host>/configuration.nix`.
- **Adding a CLI Tool**: Usually goes in `modules/home-manager/` or `hosts/<host>/home.nix`.
- **Adding a GUI App**:
  - If web-facing/proprietary: Use `nixpak` (sandboxing).
  - If standard: Add to `home.nix`.
