import os
import subprocess
import json
import shutil
from .core import mcp, DEFAULT_FLAKE_PATH
from .knowledge import semantic_search


@mcp.tool()
def get_tool_help(binary: str):
    """Run --help on a local binary to see exact usage and flags."""
    try:
        if subprocess.run(["which", binary], capture_output=True).returncode != 0:
            return f"Error: {binary} not found in PATH."
        result = subprocess.run([binary, "--help"], capture_output=True, text=True)
        if result.returncode != 0:
            result = subprocess.run([binary, "help"], capture_output=True, text=True)
        return f"STDOUT:\n{result.stdout}\n\nSTDERR:\n{result.stderr}"
    except Exception as e:
        return str(e)


@mcp.tool()
def analyze_logs(unit: str = None, machine: str = None, lines: int = 50):
    """
    Fetch and analyze recent logs using ai-logs.py.
    Provides a high-level assessment of any errors found.
    """
    try:
        cmd = [
            "python3",
            os.path.join(DEFAULT_FLAKE_PATH, "tools/ai-logs.py"),
            "--json",
            "-n",
            str(lines),
        ]
        if unit:
            cmd.extend(["-u", unit])
        if machine:
            cmd.extend(["-m", machine])

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            return {"error": f"Log analysis failed: {result.stderr}"}

        logs = json.loads(result.stdout)
        if not logs:
            return "No errors found in the specified logs. System looks healthy. ✅"

        # Group by unit for better summary
        summary = {}
        for log in logs:
            u = log.get("unit", "unknown")
            if u not in summary:
                summary[u] = []
            summary[u].append(log.get("message", ""))

        return {
            "status": "Errors Detected",
            "log_count": len(logs),
            "affected_units": list(summary.keys()),
            "summary": summary,
        }
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def troubleshoot_unit(unit: str):
    """
    Deep troubleshoot a systemd unit by correlating logs with knowledge base.
    """
    try:
        logs = analyze_logs(unit=unit, lines=20)
        knowledge = semantic_search(query=unit)

        report = {
            "unit": unit,
            "recent_logs": logs,
            "potential_matches": knowledge,
            "recommendation": "Analyze the logs above against the knowledge matches. If CUDA related, check EULA or driver version.",
        }
        return report
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def send_notification(message: str, title: str = "Workspace Atlas"):
    """Send a desktop notification."""
    try:
        if shutil.which("notify-send"):
            subprocess.run(["notify-send", "-a", "Atlas", title, message])
            return "Notification sent."
        return "notify-send not found."
    except Exception as e:
        return {"error": str(e)}
