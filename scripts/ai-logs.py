#!/usr/bin/env python3
import subprocess
import json
import sys
import argparse
from datetime import datetime

def get_machine_status(machine):
    """Check if a machine is running using machinectl."""
    try:
        result = subprocess.run(["machinectl", "status", machine], capture_output=True, text=True)
        return result.returncode == 0
    except FileNotFoundError:
        return False

def get_recent_errors(lines=50, unit=None, machine=None):
    """
    Fetch recent error messages from journalctl and format them for AI agents.
    """
    if machine and not get_machine_status(machine):
        return {"offline": f"Machine '{machine}' is currently offline or not found."}

    cmd = ["journalctl", "-p", "3", "-n", str(lines), "--output", "json"]
    if unit:
        cmd.extend(["-u", unit])
    if machine:
        cmd.extend(["--machine", machine])
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        logs = []
        for line in result.stdout.splitlines():
            try:
                data = json.loads(line)
                # Simplify the log entry for AI consumption
                entry = {
                    "timestamp": datetime.fromtimestamp(int(data.get("__REALTIME_TIMESTAMP", 0)) / 1000000).isoformat(),
                    "unit": data.get("UNIT", data.get("_SYSTEMD_UNIT", "unknown")),
                    "message": data.get("MESSAGE", ""),
                    "priority": data.get("PRIORITY", "")
                }
                logs.append(entry)
            except (json.JSONDecodeError, ValueError):
                continue
        return logs
    except subprocess.CalledProcessError as e:
        return {"error": f"Failed to fetch logs: {e.stderr}"}

def main():
    parser = argparse.ArgumentParser(description="AI-friendly semantic log viewer")
    parser.add_argument("-n", "--lines", type=int, default=30, help="Number of log lines to fetch")
    parser.add_argument("-u", "--unit", type=str, help="Specific systemd unit to filter by")
    parser.add_argument("-m", "--machine", type=str, help="Filter by NixOS container/machine name")
    parser.add_argument("--json", action="store_true", help="Output in raw JSON format")
    parser.add_argument("--sink", action="store_true", help="Update the persistent health sink")
    
    args = parser.parse_args()
    
    logs = get_recent_errors(args.lines, args.unit, args.machine)
    
    # Update health sink if requested
    if args.sink:
        import os
        sink_path = os.path.expanduser("~/.cache/ai-health.json")
        try:
            os.makedirs(os.path.dirname(sink_path), exist_ok=True)
            with open(sink_path, "w") as f:
                summary = {
                    "last_check": datetime.now().isoformat(),
                    "error_count": len(logs) if isinstance(logs, list) else 0,
                    "status": "Healthy" if not logs else "Degraded",
                    "recent_units": list(set([l.get("unit") for l in logs])) if isinstance(logs, list) else []
                }
                json.dump(summary, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to update sink: {e}", file=sys.stderr)

    if args.json:
        print(json.dumps(logs, indent=2))
    else:
        if isinstance(logs, dict):
            if "offline" in logs:
                print(f"INFO: {logs['offline']} (Services are on-demand) ✅")
                sys.exit(0)
            if "error" in logs:
                print(f"FAILED: {logs['error']}")
                sys.exit(1)
            
        if not logs:
            print(f"No recent errors found{' in ' + args.machine if args.machine else ''}. System looks healthy. ✅")
            return

        print(f"--- Semantic Log Summary (Last {len(logs)} errors) ---")
        for log in logs:
            print(f"[{log['timestamp']}] {log['unit']}: {log['message']}")

if __name__ == "__main__":
    main()
