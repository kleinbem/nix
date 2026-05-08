import 'common.just'

set working-directory := ".."

# --- Deployment ---

[group("Fleet")]
[confirm("🚀 Deploy configuration to the ENTIRE FLEET via Colmena?")]
deploy-fleet:
    @echo "🚀 Deploying to entire fleet via Colmena..."
    colmena apply --show-trace

[group("Fleet")]
deploy-orin:
    @echo "🟢 Deploying to Orin Nano..."
    colmena apply --on orin-nano

[group("Fleet")]
deploy-edge:
    @echo "📡 Deploying to AI Edge (Orin + Raspberry Pi)..."
    colmena apply --on orin-nano,rpi5-1,rpi5-2

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
[confirm("💿 WIPE the Orin Nano and perform a fresh NixOS installation? This is destructive.")]
orin-install target="root@orin-nano.local":
    @echo "💿 Preparing Orin Nano for NixOS..."
    @nix run github:nix-community/disko -- --mode zap_create_mount ./hosts/orin-nano/disko.nix
    @nixos-install --flake .#orin-nano --target-host {{target}}

[group("Security")]
[confirm("🔐 Seal the TPM key on the Orin Nano? This can only be done once after boot.")]
orin-seal:
    @echo "🔐 Sealing Orin Nano TPM keys..."
    @ssh root@orin-nano.local "tpm2_pcrseal -g sha256 -l 7 -o /persist/tpm-seal.bin"
