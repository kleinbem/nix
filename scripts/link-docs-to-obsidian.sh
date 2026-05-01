#!/usr/bin/env bash

# Documentation Linker for Obsidian
# Purpose: Symlink repository knowledge bases into the Obsidian vault for easy browsing.

VAULT_PATH="$HOME/Notes"
KNOWLEDGE_ROOT="$VAULT_PATH/System/Knowledge"
WORKSPACE_ROOT="$HOME/Develop/github.com/kleinbem/nix"

mkdir -p "$KNOWLEDGE_ROOT"

echo "🔗 Linking workspace knowledge to Obsidian..."

# Link the main repo knowledge
if [ -d "$WORKSPACE_ROOT/.agent/knowledge" ]; then
  echo "  - Linking Main Repo..."
  ln -sfn "$WORKSPACE_ROOT/.agent/knowledge" "$KNOWLEDGE_ROOT/Main"
fi

# Link sub-repo knowledge if it exists
REPOS=$(find "$WORKSPACE_ROOT" -maxdepth 1 -name "nix-*" -type d)

for repo in $REPOS; do
  repo_name=$(basename "$repo")
  if [ -d "$repo/.agent/knowledge" ]; then
    echo "  - Linking $repo_name..."
    ln -sfn "$repo/.agent/knowledge" "$KNOWLEDGE_ROOT/$repo_name"
  fi
done

echo "✅ Documentation linked to $KNOWLEDGE_ROOT"
