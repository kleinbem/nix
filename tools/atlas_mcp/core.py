import os
from mcp.server.fastmcp import FastMCP

# We define the paths relative to this core file.
# atlas_mcp/core.py is inside tools/atlas_mcp/
# SCRIPT_DIR is tools/
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FLAKE_PATH = os.path.dirname(SCRIPT_DIR)

mcp = FastMCP("workspace-atlas")

# Shared paths and constants
VAULT_PATH = os.path.join(os.path.expanduser("~"), "Documents/Notes")
FIREFOX_PATH = os.path.expanduser("~/.mozilla/firefox")
KNOWLEDGE_DIR = os.path.join(DEFAULT_FLAKE_PATH, ".agent/knowledge")
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/drive.readonly",
]
GOOGLE_TOKEN_PATH = os.path.join(DEFAULT_FLAKE_PATH, "nix-secrets/google_token.json")
GOOGLE_CREDS_PATH = os.path.join(
    DEFAULT_FLAKE_PATH, "nix-secrets/google_credentials.json"
)
STATE_FILE = os.path.join(DEFAULT_FLAKE_PATH, "scratch/workspace_state.json")
PAPERLESS_TOKEN_PATH = os.path.join(
    DEFAULT_FLAKE_PATH, "nix-secrets/paperless_token.txt"
)
