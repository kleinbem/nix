#!/usr/bin/env bash
# Antigravity Metrics Tracker 📊
# Appends build stats to .agent/metrics/history.csv

METRICS_FILE=".agent/metrics/history.csv"
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOST=$(hostname)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "dirty")

# Initialize CSV if missing
if [ ! -f "$METRICS_FILE" ]; then
  echo "date,host,commit,store_paths_count,size_estimate" >"$METRICS_FILE"
fi

# Count paths in the current system closure (rough complexity metric)
# We use the current system link /run/current-system
if [ -L "/run/current-system" ]; then
  PATH_COUNT=$(nix path-info -r /run/current-system | wc -l)
  SIZE_ESTIMATE=$(du -shL /run/current-system | cut -f1)
else
  PATH_COUNT="0"
  SIZE_ESTIMATE="0"
fi

echo "$DATE,$HOST,$COMMIT,$PATH_COUNT,$SIZE_ESTIMATE" >>"$METRICS_FILE"
echo "📊 Metrics logged: $PATH_COUNT store paths ($SIZE_ESTIMATE)."
