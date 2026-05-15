#!/usr/bin/env python3
import time
import subprocess
import json
import os
from datetime import datetime

# ATLAS Infrastructure AI - Autonomous Guardian V1.0
# Periodically checks system health and attempts autonomous fixes.

INTERVAL = 300  # 5 minutes
WORKSPACE_ROOT = "/home/martin/Develop/github.com/kleinbem/nix"
LOG_FILE = os.path.join(WORKSPACE_ROOT, "scratch/guardian.log")

def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] {message}"
    print(entry)
    with open(LOG_FILE, "a") as f:
        f.write(entry + "\n")

def run_health_check():
    """Run the workspace-atlas check_ai_stack_health tool via MCP if possible, or fallback to subprocess."""
    log("Running scheduled health check...")
    # We can't easily call FastMCP from another script without JSON-RPC, 
    # so we'll directly call the logic or use the existing scripts.
    try:
        # Check containers
        cmd = ["python3", os.path.join(WORKSPACE_ROOT, "scripts/ai-logs.py"), "--json"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            errors = json.loads(result.stdout)
            if errors:
                log(f"Detected {len(errors)} system errors.")
                # Self-healing logic: for each error, check if it's a known unit and restart it
                units = set(e.get("unit") for e in errors if e.get("unit"))
                for unit in units:
                    if unit.startswith("container@"):
                        log(f"Attempting restart of {unit}...")
                        subprocess.run(["sudo", "systemctl", "restart", unit])
            else:
                log("System looks healthy. ✅")
    except Exception as e:
        log(f"Guardian error: {str(e)}")

def main():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    log("Guardian started. Monitoring infrastructure...")
    while True:
        run_health_check()
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
