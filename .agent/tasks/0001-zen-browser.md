---
status: todo
priority: high
tags: [nix, internet, AI, PWA]
created: 2026-03-24
---
# 🚀 Mission: Zen Browser "AI-Powerhouse" for NixOS

**Objective:** Configure a declarative NixOS setup for the Zen Browser (Firefox-based) with native AI capabilities, side-by-side developer workflows, and full PWA (Progressive Web App) support.

---

## 1. Core Installation (Flake Strategy)
* **Source:** Use the Zen Browser community flake: `github:0xc000022070/zen-browser-flake`.
* **Integration:**
    * Add to `flake.nix` inputs.
    * Set `zen-browser.inputs.nixpkgs.follows = "nixpkgs"` to ensure binary compatibility.
    * Add `inputs.zen-browser.packages."${pkgs.system}".default` to `environment.systemPackages`.

## 2. AI-Native "Assistant" Configuration
* **Task:** Enable the underlying Gecko ML engine and Zen's AI UI flags.
* **Target:** `programs.zen-browser.profiles.<name>.settings`.
* **Key Parameters:**
    ```nix
    {
      "browser.ml.chat.enabled" = true;            # Enable Mozilla's AI framework
      "browser.ml.chat.sidebar" = true;            # Dock AI to the Zen sidebar
      "browser.ml.chat.provider" = "[https://chat.openai.com](https://chat.openai.com)"; # Default Assistant
      "zen.view.split-view.enabled" = true;        # Enable side-by-side AI/Dev layout
      "javascript.options.wasm" = true;            # Required for on-device AI models
    }
    ```

## 3. "Perfect" PWA Support (Nix-Bridge)
* **Problem:** Firefox/Zen lacks native Chromium-style PWAs.
* **Solution:** Implement the `firefoxpwa` (PWAsForFirefox) native messenger bridge.
* **System Config:**
    * Include `pkgs.firefoxpwa` in `environment.systemPackages`.
    * Enable the bridge: `programs.zen-browser.nativeMessagingHosts = [ pkgs.firefoxpwa ];`.
* **Extension:** Ensure the `pwas-for-firefox` extension is pre-installed via `pkgs.nur.repos.rycee.firefox-addons`.

## 4. Developer & Privacy Hardening
* **Extensions:**
    * `ublock-origin` (Content blocking)
    * `multi-account-containers` (Context isolation for Python/AI dev)
    * `darkreader` (Developer eye-strain)
* **UI Tweaks:**
    * Enable **Vertical Tabs** (Zen signature).
    * Set **Compact Mode** to `true` for maximum screen real estate.
    * Enable **HTTPS-Only Mode**.

---

## 📋 The "Antigravity" Execution Prompt
> "I need a declarative NixOS module (Flake-based) for the Zen Browser. Use the `zen-browser-flake`. 
> 
> 1. Configure the `firefoxpwa` native messenger bridge for full PWA support. 
> 2. Enable all `browser.ml.chat` flags in the profile settings to activate the AI sidebar. 
> 3. Enable `zen.view.split-view` for side-by-side coding and AI assistance. 
> 4. Add the following extensions via NUR: uBlock Origin, Multi-Account Containers, and PWAsForFirefox. 
> 5. Format the output as a clean Nix module for my `configuration.nix`."