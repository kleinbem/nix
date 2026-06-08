#!/usr/bin/env bash
# sync-agent-context.sh - Generates a System Reference for the AI assistant.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
OUTPUT_FILE="$REPO_ROOT/nix-config/docs/SYSTEM_REFERENCE.md"

echo "🔍 Generating System Reference for Antigravity..."

# Use nix eval to get structured data from inventory.nix
# We wrap it in a dummy flake or just eval the file directly if it's standalone
HOSTS=$(nix eval --json --file "$REPO_ROOT/nix-config/inventory.nix" hosts --apply "builtins.attrNames" | jq -r '.[]')
SERVICES=$(nix eval --json --file "$REPO_ROOT/nix-config/inventory.nix" network.nodes --apply "builtins.attrNames" | jq -r '.[]')

cat <<EOF >"$OUTPUT_FILE"
# 🏗️ System Reference (Auto-generated)
*Last Updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")*

> [!IMPORTANT]
> This file contains the "ground truth" for the current NixOS infrastructure. 
> Antigravity MUST read this file at the start of any configuration task.

## 📦 Core Revisions
EOF

# Extract nixpkgs revision
NIXPKGS_REV=$(grep -A 10 '"nixpkgs":' "$REPO_ROOT/flake.lock" | grep '"rev":' | head -n 1 | awk -F'"' '{print $4}')
echo "- **nixpkgs**: [\`$NIXPKGS_REV\`](https://github.com/NixOS/nixpkgs/commit/$NIXPKGS_REV)" >>"$OUTPUT_FILE"

# Extract other key inputs
inputs=("home-manager" "devenv" "sops-nix" "nix-config" "nix-packages" "nix-hardware")
for input in "${inputs[@]}"; do
  REV=$(grep -A 10 "\"$input\":" "$REPO_ROOT/flake.lock" | grep '"rev":' | head -n 1 | awk -F'"' '{print $4}')
  if [ -n "$REV" ]; then
    echo "- **$input**: \`$REV\`" >>"$OUTPUT_FILE"
  fi
done

echo -e "\n## 🖥️ Managed Hosts" >>"$OUTPUT_FILE"
for host in $HOSTS; do
  echo "- **$host**" >>"$OUTPUT_FILE"
done

echo -e "\n## 📡 Network Services" >>"$OUTPUT_FILE"
for svc in $SERVICES; do
  echo "- **$svc**" >>"$OUTPUT_FILE"
done

echo -e "\n## 🛠️ Workspace Status" >>"$OUTPUT_FILE"
if command -v devenv &>/dev/null; then
  echo "- **Devenv**: Available" >>"$OUTPUT_FILE"
else
  echo "- **Devenv**: Not found in path" >>"$OUTPUT_FILE"
fi

# Check for Guardian service
if systemctl --user is-active workspace-guardian.service &>/dev/null; then
  echo "- **Autonomous Guardian**: Active ✅" >>"$OUTPUT_FILE"
else
  echo "- **Autonomous Guardian**: Inactive ❌" >>"$OUTPUT_FILE"
fi

echo -e "\n## 🤖 AI Capabilities (MCP Tools)" >>"$OUTPUT_FILE"
# Extract tools from workspace-mcp.py
grep "@mcp.tool()" -A 1 "$REPO_ROOT/scripts/workspace-mcp.py" | grep "def " | sed 's/def //; s/(.*):/- **/; s/$/\**/' >>"$OUTPUT_FILE"

echo "✅ System Reference updated at $OUTPUT_FILE"

# Regenerate the machine-readable my.* options index (used by AI for blast-radius lookups)
if command -v python3 &>/dev/null; then
  python3 "$REPO_ROOT/scripts/generate-options-index.py" || echo "⚠️  Options index generation failed (non-fatal)"
else
  echo "⚠️  python3 not found — skipping options index regeneration"
fi
