#!/usr/bin/env python3
import json
import sys
import os
import subprocess
from typing import List, Dict, Any

# Workspace Atlas MCP - V2.0
# Expanded to support deep NixOS configuration inspection

def get_active_profile():
    """Detects the currently active NixOS specialisation."""
    try:
        spec_path = "/run/current-system/specialisation"
        if not os.path.exists(spec_path):
            return "minimal (base)"
        
        # In NixOS, the active specialisation isn't always easy to tell just from the FS,
        # but we can check which specialisation's 'bin/switch' was last used or check symlinks.
        # For now, we'll return the list of available ones if we can't be sure.
        specs = os.listdir(spec_path)
        return {"active_potential": specs, "note": "Check 'active-specialisation' if available"}
    except Exception as e:
        return {"error": str(e)}

def eval_nix(expr: str, flake_path: str = "."):
    """Evaluates a Nix expression from the flake."""
    try:
        # We target the nixos-nvme configuration specifically as it's the main host
        full_expr = f"(import {flake_path} {{}}).nixosConfigurations.nixos-nvme.config.{expr}"
        
        result = subprocess.run(
            ["nix", "eval", "--json", "--impure", "--expr", full_expr],
            capture_output=True, text=True, check=True
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        return {"error": f"Nix evaluation failed: {e.stderr}"}
    except Exception as e:
        return {"error": str(e)}

def get_containers():
    """Specifically lists all custom containers defined in my.containers."""
    try:
        # This reaches into your custom module structure
        expr = "my.containers"
        containers = eval_nix(expr)
        
        if "error" in containers:
            return containers
            
        summary = {}
        for name, cfg in containers.items():
            summary[name] = {
                "enable": cfg.get("enable", False),
                "ip": cfg.get("ip", "unknown"),
                "hostDataDir": cfg.get("hostDataDir", "N/A")
            }
        return summary
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
                    "capabilities": {"tools": {"list": True}},
                    "serverInfo": {"name": "workspace-atlas", "version": "0.2.0"}
                }
            elif method == "tools/list":
                response["result"] = {
                    "tools": [
                        {
                            "name": "get_active_profile",
                            "description": "Detect the currently active NixOS specialisation/mode",
                            "inputSchema": {"type": "object", "properties": {}}
                        },
                        {
                            "name": "list_containers",
                            "description": "List all NixOS containers and their current configuration",
                            "inputSchema": {"type": "object", "properties": {}}
                        },
                        {
                            "name": "eval_nix_option",
                            "description": "Evaluate a specific Nix configuration option",
                            "inputSchema": {
                                "type": "object",
                                "properties": {
                                    "option": {"type": "string", "description": "The option path (e.g., 'services.ollama.enable')"}
                                },
                                "required": ["option"]
                            }
                        },
                        {
                            "name": "get_workspace_summary",
                            "description": "Get a summary of the Nix workspace structure",
                            "inputSchema": {"type": "object", "properties": {}}
                        }
                    ]
                }
            elif method == "tools/call":
                tool_name = params.get("name")
                tool_args = params.get("arguments", {})
                
                result_data = {}
                if tool_name == "get_active_profile":
                    result_data = get_active_profile()
                elif tool_name == "list_containers":
                    result_data = get_containers()
                elif tool_name == "eval_nix_option":
                    result_data = eval_nix(tool_args.get("option"))
                elif tool_name == "get_workspace_summary":
                    # Reuse existing logic or simple placeholder
                    result_data = {"root": os.getcwd()}
                
                response["result"] = {"content": [{"type": "text", "text": json.dumps(result_data, indent=2)}]}
            
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Error: {str(e)}\n")

if __name__ == "__main__":
    main()
