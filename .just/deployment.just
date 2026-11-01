import 'common.just'

set working-directory := ".."

# --- Cross-cutting deployment recipes ---
# Host-specific deploys live in nix-config/.just/deployment.just
# (e.g. `just in nix-config deployment::deploy-fleet`).

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
    @./tools/tf-apply.sh
