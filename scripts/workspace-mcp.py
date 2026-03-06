#!/usr/bin/env python3
import json
import sys
import os
import subprocess
from typing import List, Dict, Any

# Simple MCP server for Nix Workspace Discovery
# Protocol: Read JSON from stdin, write JSON to stdout

def get_workspace_info():
    """Returns information about the Nix workspace structure."""
    try:
        # Get list of local repositories (submodules)
        repos = [d for d in os.listdir('.') if os.path.isdir(d) and d.startswith('nix-')]
        
        info = {
            "root": os.getcwd(),
            "repositories": repos,
            "architecture": "Meta-Workspace (nix) -> Aggregates Sub-Flakes",
            "key_files": {
                "flake.nix": "Main entry point",
                "justfile": "Workspace commands",
                ".agent/rules.md": "Assistant guidelines"
            }
        }
        return info
    except Exception as e:
        return {"error": str(e)}

def list_nix_outputs(flake_path: str):
    """Lists outputs of a specific flake."""
    try:
        result = subprocess.run(
            ["nix", "flake", "show", "--json", flake_path],
            capture_output=True, text=True, check=True
        )
        return json.loads(result.stdout)
    except Exception as e:
        return {"error": str(e)}

def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        
        try:
            request = json.loads(line)
            method = request.get("method")
            params = request.get("params", {})
            
            response = {"jsonrpc": "2.0", "id": request.get("id")}
            
            if method == "initialize":
                response["result"] = {
                    "capabilities": {
                        "tools": {
                            "list": True
                        }
                    },
                    "serverInfo": {"name": "workspace-atlas", "version": "0.1.0"}
                }
            elif method == "tools/list":
                response["result"] = {
                    "tools": [
                        {
                            "name": "get_workspace_summary",
                            "description": "Get a summary of the Nix workspace structure",
                            "inputSchema": {"type": "object", "properties": {}}
                        },
                        {
                            "name": "inspect_flake_outputs",
                            "description": "List the outputs of a specific nix flake in the workspace",
                            "inputSchema": {
                                "type": "object", 
                                "properties": {
                                    "path": {"type": "string", "description": "Path to the flake directory (e.g., './nix-config')"}
                                },
                                "required": ["path"]
                            }
                        }
                    ]
                }
            elif method == "tools/call":
                tool_name = params.get("name")
                tool_args = params.get("arguments", {})
                
                if tool_name == "get_workspace_summary":
                    response["result"] = {"content": [{"type": "text", "text": json.dumps(get_workspace_info(), indent=2)}]}
                elif tool_name == "inspect_flake_outputs":
                    path = tool_args.get("path")
                    response["result"] = {"content": [{"type": "text", "text": json.dumps(list_nix_outputs(path), indent=2)}]}
                else:
                    response["error"] = {"code": -32601, "message": f"Tool not found: {tool_name}"}
            
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
        except Exception as e:
            # Silent error for protocol robustness, but log to stderr
            sys.stderr.write(f"Error: {str(e)}\n")

if __name__ == "__main__":
    main()
