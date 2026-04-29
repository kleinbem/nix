#!/usr/bin/env bash

# generate-secrets.sh
# Generates random values for the internal secrets in your SOPS config.

echo "--- Random Secret Generation ---"
echo ""

generate_secret() {
  local name=$1
  local type=$2
  local value=""

  if command -v openssl >/dev/null 2>&1; then
    if [ "$type" == "base64" ]; then
      value=$(openssl rand -base64 32)
    else
      value=$(openssl rand -hex 24)
    fi
  else
    # Fallback to /dev/urandom if openssl is missing
    if [ "$type" == "base64" ]; then
      value=$(head -c 32 /dev/urandom | base64)
    else
      value=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
  fi

  echo "NAME:  $name"
  echo "VALUE: $value"
  echo "-----------------------------------"
}

generate_secret "langfuse_nextauth_secret" "base64"
generate_secret "langfuse_salt" "hex"
generate_secret "n8n_encryption_key" "hex"
generate_secret "webui_secret_key" "base64"

echo ""
echo "Instructions:"
echo "1. Run 'cd nix-secrets && sops secrets.yaml'"
echo "2. Copy these values into the corresponding PLACEHOLDER fields."
echo "3. For external keys (GitHub, Brave, etc.), check the 'secrets_guide.md' for links."
