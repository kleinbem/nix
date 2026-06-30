#!/usr/bin/env -S python3 -u
# ruff: noqa: E402, F401
"""
SOURCE OF TRUTH: tools/workspace-mcp.py
This is a lightweight wrapper that bootstraps the atlas_mcp package structure.
It allows the MCP server to remain at the expected path without breaking existing Nix configurations.
"""

import os
import sys
import json

# Ensure we can import the local atlas_mcp package
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from atlas_mcp.core import mcp
import atlas_mcp.jujutsu
import atlas_mcp.network
import atlas_mcp.workspace
import atlas_mcp.nix_tools
import atlas_mcp.skills
import atlas_mcp.knowledge
import atlas_mcp.system
import atlas_mcp.browser
import atlas_mcp.security
import atlas_mcp.ai_services
import atlas_mcp.inventory
import atlas_mcp.google
import atlas_mcp.paperless

if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Simple CLI mode for manual testing
        tool_name = sys.argv[1]
        print(f"CLI manual mode. Check individual module to run: {tool_name}")
    else:
        mcp.run()
