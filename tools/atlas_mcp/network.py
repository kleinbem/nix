import json
import subprocess
from .core import mcp


@mcp.tool()
def netbird_status():
    """Check the status of the NetBird mesh network and connected peers."""
    try:
        result = subprocess.run(
            ["netbird", "status", "--output", "json"], capture_output=True, text=True
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        # Fallback to plain text if JSON output is not supported or fails
        result = subprocess.run(["netbird", "status"], capture_output=True, text=True)
        return result.stdout
    except Exception as e:
        return str(e)


@mcp.tool()
def syncthing_status():
    """Check Syncthing synchronization status."""
    try:
        # We try to use the CLI if available
        result = subprocess.run(
            ["syncthing", "cli", "config", "devices"], capture_output=True, text=True
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        return "Syncthing CLI not responding. Ensure the service is running."
    except Exception as e:
        return str(e)
