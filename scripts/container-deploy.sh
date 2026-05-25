#!/usr/bin/env bash
set -e

CONTAINER_NAME=$1
SOURCE_PATH=$2

if [ -z "$CONTAINER_NAME" ] || [ -z "$SOURCE_PATH" ]; then
  echo "Usage: $0 <container-name> <source-path>"
  echo "Example: $0 n8n ./n8n-container-result"
  exit 1
fi

if [ ! -e "$SOURCE_PATH" ]; then
  echo "Error: Source path '$SOURCE_PATH' does not exist."
  exit 1
fi

# Ensure machines directory exists
sudo mkdir -p /var/lib/machines/"$CONTAINER_NAME"

# Link the closure
REAL_PATH=$(readlink -f "$SOURCE_PATH")
echo "Linking $REAL_PATH to /var/lib/machines/$CONTAINER_NAME/current"
sudo ln -sfn "$REAL_PATH" /var/lib/machines/"$CONTAINER_NAME"/current

# Restart the container service
echo "Restarting container@$CONTAINER_NAME service..."
sudo systemctl restart "container@$CONTAINER_NAME.service"

echo "Done!"
