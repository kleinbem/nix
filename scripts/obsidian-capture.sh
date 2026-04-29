#!/usr/bin/env bash

# Obsidian Quick Capture Script
# Purpose: Quickly append a note to the Obsidian Inbox without opening the UI.

VAULT_PATH="$HOME/Notes"
INBOX_FILE="$VAULT_PATH/Inbox.md"

# Ensure the vault directory exists
if [ ! -d "$VAULT_PATH" ]; then
  echo "📂 Creating Obsidian Vault directory at $VAULT_PATH..."
  mkdir -p "$VAULT_PATH"
fi

# Get the message from arguments
MESSAGE="$*"

if [ -z "$MESSAGE" ]; then
  echo "📝 Enter your note (Ctrl+D to finish):"
  MESSAGE=$(cat)
fi

if [ -z "$MESSAGE" ]; then
  echo "⚠️  Empty note, skipping."
  exit 0
fi

# Append with metadata
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
{
  echo -e "\n---"
  echo "### 📥 Captured: $TIMESTAMP"
  echo "**Tags**: #inbox #capture"
  echo "**Source**: Terminal"
  echo ""
  echo "$MESSAGE"
  echo "---"
} >>"$INBOX_FILE"

echo "✅ Note captured to Inbox.md"
