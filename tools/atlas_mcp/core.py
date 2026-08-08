import os

from mcp.server.fastmcp import FastMCP

# We define the paths relative to this core file.
# atlas_mcp/core.py is inside tools/atlas_mcp/
# SCRIPT_DIR is tools/
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FLAKE_PATH = os.path.dirname(SCRIPT_DIR)
# DEFAULT_FLAKE_PATH is nix/ (the conductor dir); the sibling repos, including
# kleinbem-secrets, live one level up in the flat workspace root.
WORKSPACE_ROOT = os.path.dirname(DEFAULT_FLAKE_PATH)

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
# google_credentials.json used to be read as a plaintext file from a
# nix-secrets/ directory that never actually existed under nix/ in the flat
# sibling-repo layout (stale pre-consolidation path). The OAuth client
# secret now lives sops-encrypted in kleinbem-secrets as
# infra/terraform.yaml's google_oauth_client_json key, decrypted in-memory
# via sops (see google.py) rather than ever touching disk.
GOOGLE_OAUTH_SOPS_FILE = os.path.join(WORKSPACE_ROOT, "kleinbem-secrets/infra/terraform.yaml")
GOOGLE_OAUTH_SOPS_KEY = "google_oauth_client_json"
# Self-generated OAuth token cache and the (never sops-managed, drop-in-manually)
# Paperless API token both live under nix/scratch/ — the existing convention
# for gitignored local runtime state (see STATE_FILE below), not a secret
# vault path.
GOOGLE_TOKEN_PATH = os.path.join(DEFAULT_FLAKE_PATH, "scratch/google_token.json")
STATE_FILE = os.path.join(DEFAULT_FLAKE_PATH, "scratch/workspace_state.json")
PAPERLESS_TOKEN_PATH = os.path.join(DEFAULT_FLAKE_PATH, "scratch/paperless_token.txt")
