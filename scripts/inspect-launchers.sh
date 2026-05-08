#!/usr/bin/env bash
APP_DIR="$HOME/.local/share/applications"
for file in "$APP_DIR"/org.mozilla.firefox.webapp-*.desktop "$APP_DIR"/FFPWA-*.desktop; do
  [ -e "$file" ] || continue
  echo "--- $(basename "$file") ---"
  grep "^Exec=" "$file"
done
