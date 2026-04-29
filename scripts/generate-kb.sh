#!/usr/bin/env bash
set -e

# Base Directory for Reference Docs
REF_DIR="docs/reference"
mkdir -p "$REF_DIR"

echo "📚 Generating Knowledge Base in $REF_DIR..."

# --- Function: Extract Binary Help ---
extract_binary_help() {
  local tool=$1
  local package=$2
  local target_dir="$REF_DIR/$tool"

  echo "   extracting $tool (from $package)..."
  mkdir -p "$target_dir"

  # Run the binary from the flake to get the help output
  nix run "$package" -- --help >"$target_dir/help.txt" 2>&1 || true

  # Special cases for extra info
  if [ "$tool" == "caddy" ]; then
    nix run "$package" -- list-modules >"$target_dir/modules.txt" 2>&1 || true
  fi
}

# --- Function: Extract Flake Input Docs ---
extract_input_docs() {
  local input_name=$1
  local target_dir="$REF_DIR/$input_name"

  echo "   extracting input $input_name..."
  mkdir -p "$target_dir"

  # Get the store path of the input
  # Strategy 1: Try to look it up in local lockfile metadata.
  # Note: 'path' is often missing for git inputs in metadata.
  # We try to find a 'storePath' or 'path' in the locked node.
  LOCAL_PATH=$(nix flake metadata --json . | jq -r ".locks.nodes.\"$input_name\".path // .locks.nodes.\"$input_name\".locked.path // empty")

  if [ -n "$LOCAL_PATH" ] && [ -d "$LOCAL_PATH" ]; then
    INPUT_PATH="$LOCAL_PATH"
  else
    echo "      ...local lookup failed, attempting to fetch input specific archive..."
    # Strategy 2: generic fetch of the input.
    # This is safer than archiving '.' which might just return self.
    # We need to know the original URI to fetch it specifically if we can't find it in locks.
    # For now, we will assume it is a clear flake input and try to 'nix flake archive' it via flake url if we know it.
    # Since we don't know the URL dynamically easily without parsing more JSON, we will fall back to the known URL for nixpak.

    if [ "$input_name" == "nixpak" ]; then
      INPUT_PATH=$(nix flake archive --json "github:nixpak/nixpak" | jq -r .path)
    else
      # Generic fallback: try to find the url from metadata and archive that
      INPUT_URL=$(nix flake metadata --json . | jq -r ".locks.nodes.\"$input_name\".original.url // empty")
      if [ -n "$INPUT_URL" ]; then
        INPUT_PATH=$(nix flake archive --json "$INPUT_URL" | jq -r .path)
      fi
    fi
  fi

  if [ -d "$INPUT_PATH" ]; then
    echo "      found at $INPUT_PATH"
    # Copy README
    cp "$INPUT_PATH/README.md" "$target_dir/" 2>/dev/null || true
    # Copy docs folder if it exists
    if [ -d "$INPUT_PATH/docs" ]; then
      cp -r "$INPUT_PATH/docs" "$target_dir/"
    fi
    # Copy *.md files from root if they look like docs
    find "$INPUT_PATH" -maxdepth 1 -name "*.md" -not -name "README.md" -exec cp {} "$target_dir/" \;
  else
    echo "      ⚠️  Could not locate store path for $input_name"
  fi
}

# --- 1. Tools ---
extract_binary_help "caddy" "nixpkgs#caddy"

# --- 2. Libraries/Inputs ---
extract_input_docs "nixpak"
# Add more inputs here as needed (e.g., "disko", "home-manager")

echo "✅ Knowledge Base Updated!"
