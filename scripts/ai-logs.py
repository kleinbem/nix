#!/usr/bin/env python3
import subprocess
import json
import sys
import argparse
from datetime import datetime

def get_recent_errors(lines=50, unit=None):
    """
    Fetch recent error messages from journalctl and format them for AI agents.
    """
    cmd = ["journalctl", "-p", "3", "-n", str(lines), "--output", "json"]
    if unit:
        cmd.extend(["-u", unit])
    
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
    parser.add_argument("--json", action="store_true", help="Output in raw JSON format")
    
    args = parser.parse_args()
    
    logs = get_recent_errors(args.lines, args.unit)
    
    if args.json:
        print(json.dumps(logs, indent=2))
    else:
        if isinstance(logs, dict) and "error" in logs:
            print(f"FAILED: {logs['error']}")
            sys.exit(1)
            
        if not logs:
            print("No recent errors found. System looks healthy. ✅")
            return

        print(f"--- Semantic Log Summary (Last {len(logs)} errors) ---")
        for log in logs:
            print(f"[{log['timestamp']}] {log['unit']}: {log['message']}")

if __name__ == "__main__":
    main()
