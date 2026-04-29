#!/usr/bin/env bash

# Obsidian Vault Health Check
# Purpose: Identify sync conflicts, large files, and potential issues in the vault.

VAULT_PATH="$HOME/GoogleDrive/Obsidian/MyVault"

if [ ! -d "$VAULT_PATH" ]; then
  echo "❌ Error: Vault not found at $VAULT_PATH"
  exit 1
fi

echo "🛡️  Checking Obsidian Vault Health: $VAULT_PATH"
echo "------------------------------------------------"

# 1. Check for Sync Conflicts (Syncthing/Dropbox/etc)
CONFLICTS=$(find "$VAULT_PATH" -name "*sync-conflict*" -o -name "*conflicted copy*" | wc -l)
if [ "$CONFLICTS" -gt 0 ]; then
  echo "⚠️  Found $CONFLICTS sync conflict files!"
  find "$VAULT_PATH" -name "*sync-conflict*" -o -name "*conflicted copy*" | sed 's/^/   - /'
else
  echo "✅ No sync conflicts found."
fi

# 2. Check for Large Attachments (> 50MB)
LARGE_FILES=$(find "$VAULT_PATH" -type f -size +50M | wc -l)
if [ "$LARGE_FILES" -gt 0 ]; then
  echo "📦 Found $LARGE_FILES large attachments (>50MB):"
  find "$VAULT_PATH" -type f -size +50M -exec ls -lh {} \; | awk '{print "   - " $9 " (" $5 ")"}'
else
  echo "✅ No unusually large attachments found."
fi

# 3. Check for Empty Files (Potentially failed captures)
EMPTY_FILES=$(find "$VAULT_PATH" -type f -name "*.md" -size 0 | wc -l)
if [ "$EMPTY_FILES" -gt 0 ]; then
  echo "📄 Found $EMPTY_FILES empty markdown files:"
  find "$VAULT_PATH" -type f -name "*.md" -size 0 | sed 's/^/   - /'
else
  echo "✅ No empty notes found."
fi

# 4. Check Vault Index Size
if [ -d "$VAULT_PATH/.obsidian" ]; then
  INDEX_SIZE=$(du -sh "$VAULT_PATH/.obsidian" | awk '{print $1}')
  echo "📊 Vault metadata size (.obsidian): $INDEX_SIZE"
fi

# 5. Backup Check (Simulated)
# Since the vault is on GDrive, we assume cloud versioning is active.
# But we should remind the user to check their secondary backup.
echo "🔄 Reminder: Check your secondary backup (Obsidian Git or Restic)."

echo "------------------------------------------------"
echo "✨ Health check complete!"
