#!/usr/bin/env bash

# Obsidian PARA Organization Script
# Purpose: Moves files from the root to a PARA structure.

VAULT_PATH="$HOME/GoogleDrive/Obsidian/MyVault"

if [ ! -d "$VAULT_PATH" ]; then
  echo "❌ Error: Vault not found at $VAULT_PATH"
  exit 1
fi

echo "📂 Organizing Vault: $VAULT_PATH"

# 1. Create PARA Structure
mkdir -p "$VAULT_PATH/Inbox"
mkdir -p "$VAULT_PATH/Areas"
mkdir -p "$VAULT_PATH/Resources"
mkdir -p "$VAULT_PATH/Archives"
mkdir -p "$VAULT_PATH/Attachments"

# 2. Move root files to appropriate folders
move_if_exists() {
  local source="$VAULT_PATH/$1"
  local target="$VAULT_PATH/$2"
  if [ -e "$source" ]; then
    echo "   Moving $1 -> $2/"
    mv "$source" "$target/"
  fi
}

# --- Move Directories ---
move_if_exists "Finance" "Areas"
move_if_exists "Taekwondo" "Areas"
move_if_exists "Learning" "Resources"
move_if_exists "Chrome Os Flex" "Resources"
move_if_exists "Projects" "Projects" # Already there, but ensures it matches logic if we had one

# --- Move Files ---
move_if_exists "temp.md" "Inbox"
move_if_exists "Eltern Sport.md" "Areas"

# --- Move Attachments (Images) ---
find "$VAULT_PATH" -maxdepth 1 -name "*.png" -exec mv {} "$VAULT_PATH/Attachments/" \;
find "$VAULT_PATH" -maxdepth 1 -name "*.jpg" -exec mv {} "$VAULT_PATH/Attachments/" \;

echo "✅ Organization complete!"
