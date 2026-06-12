import 'common.just'

set working-directory := ".."

# --- Cross-cutting deployment recipes ---
# Host-specific deploys (deploy-fleet/deploy-orin/orin-*/pi-*/router-*/core-rebind-tang)
# moved to `nix-config/.just/deployment.just`. Run them with:
#   cd nix-config && just deployment::deploy-fleet
# or via the [Main] shortcuts in the root justfile.

[group("Status")]
fleet mode="minimal":
    @echo "🚢 Container Fleet Status (Mode: {{mode}})"
    @ssh root@caddy.local "caddy list-adapters"
    @nix run nixpkgs#glances

[group("Development")]
launch-dashboard:
    @echo "📊 Launching Local Dashboard..."
    @HOMEPAGE_CONFIG_DIR=$(pwd)/.dev-dashboard XDG_CACHE_HOME=$(pwd)/.dev-dashboard/cache PORT=8083 nix run nixpkgs#homepage-dashboard

[group("Cloudflare")]
[doc("Deploy Cloudflare Tunnel and wildcard CNAME records via OpenTofu")]
deploy-cloudflare:
    @./scripts/tf-apply.sh
