import json
import os
import shutil
import socket
import subprocess
import time

from .core import DEFAULT_FLAKE_PATH, WORKSPACE_ROOT, mcp
from .network import netbird_status

_INVENTORY_CACHE = None


def _get_inventory_cached():
    global _INVENTORY_CACHE
    if _INVENTORY_CACHE is not None:
        return _INVENTORY_CACHE
    try:
        inv_path = os.path.join(WORKSPACE_ROOT, "nix-config/inventory.nix")
        result = subprocess.run(
            ["nix", "eval", "--json", "--file", inv_path],
            capture_output=True,
            text=True,
            check=True,
        )
        _INVENTORY_CACHE = json.loads(result.stdout)
        return _INVENTORY_CACHE
    except Exception:
        return {}


@mcp.tool()
def get_fleet_status():
    """Check connectivity and status of all hosts in the inventory using Colmena/NetBird."""
    results = {}
    try:
        # Get inventory first
        inventory = get_inventory_summary()
        if "error" in inventory:
            return inventory

        # Check NetBird status for mesh connectivity. Peers are keyed by the
        # first label of their FQDN (orin-nano.netbird.cloud -> orin-nano).
        nb = netbird_status()
        peers = None
        if isinstance(nb, dict) and isinstance(nb.get("peers"), dict):
            peers = {}
            # Our own NetBird FQDN can carry a suffix; the hostname can't.
            peers[socket.gethostname()] = "this host"
            for p in nb["peers"].get("details") or []:
                name = (p.get("fqdn") or "").split(".")[0]
                if name:
                    peers[name] = p.get("status", "unknown")

        # inventory.nix top level is {git, hardware, hosts, network, …} —
        # the fleet lives under `hosts`, each entry {ip, tags, type}.
        for host, data in inventory.get("hosts", {}).items():
            results[host] = {
                "ip": data.get("ip", "unknown"),
                "mesh_status": (
                    "unavailable" if peers is None else peers.get(host, "not a peer")
                ),
                "tags": data.get("tags", []),
            }
    except Exception as e:
        return {"error": str(e)}
    return results


@mcp.tool()
def get_inventory_summary():
    """Get full inventory of hosts and network nodes."""
    try:
        res = _get_inventory_cached()
        if not res:
            return {"error": "Failed to evaluate inventory.nix"}
        return res
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def get_system_telemetry():
    """
    Fetch real-time hardware telemetry (CPU, Mem, Disk, Temp).
    Essential for monitoring build load and system health.
    """
    try:
        import psutil

        # CPU & Load
        cpu_pct = psutil.cpu_percent(interval=0.1)
        load = os.getloadavg()

        # Memory
        mem = psutil.virtual_memory()

        # Disk
        disk = psutil.disk_usage("/")

        # Temps (Requires sensors/psutil support)
        temps = {}
        try:
            raw_temps = psutil.sensors_temperatures()
            for name, entries in raw_temps.items():
                temps[name] = entries[0].current if entries else "N/A"
        except (AttributeError, OSError):
            pass

        # Health sink written by tools/ai-logs.sh --sink. Refresh it in the
        # background when missing, or when Degraded and older than 10 minutes,
        # so repeated calls don't each start a new run.
        health_status = "Unknown"
        sink_path = os.path.join(DEFAULT_FLAKE_PATH, "scratch/ai-health.json")
        refresh = True
        if os.path.exists(sink_path):
            with open(sink_path, "r") as f:
                sink_data = json.load(f)
            health_status = sink_data.get("status", "Unknown")
            age = time.time() - os.path.getmtime(sink_path)
            refresh = health_status == "Degraded" and age > 600
        if refresh:
            subprocess.Popen(
                [os.path.join(DEFAULT_FLAKE_PATH, "tools/ai-logs.sh"), "--sink"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        return {
            "status": "Operational",
            "system_health": health_status,
            "cpu_usage_pct": cpu_pct,
            "load_avg": load,
            "memory": {
                "total_gb": round(mem.total / (1024**3), 2),
                "used_gb": round(mem.used / (1024**3), 2),
                "available_pct": mem.available * 100 / mem.total,
            },
            "disk_root": {
                "free_gb": round(disk.free / (1024**3), 2),
                "used_pct": disk.percent,
            },
            "temperatures": temps,
        }
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def get_hardware_profile(target_host: str = "local"):
    """
    Fetch advanced hardware profile, including GPU and Jetson-specific stats.
    """
    profile = {"host": target_host, "gpu": None, "jetson": None, "thermal": {}}
    try:
        # Local GPU check
        if target_host == "local":
            if shutil.which("nvidia-smi"):
                res = subprocess.run(
                    [
                        "nvidia-smi",
                        "--query-gpu=name,utilization.gpu,memory.used,temperature.gpu",
                        "--format=csv,noheader,nounits",
                    ],
                    capture_output=True,
                    text=True,
                )
                if res.returncode == 0:
                    parts = res.stdout.strip().split(", ")
                    profile["gpu"] = {
                        "name": parts[0],
                        "load_pct": parts[1],
                        "mem_used_mb": parts[2],
                        "temp_c": parts[3],
                    }

            # Local Jetson check
            teg = shutil.which("tegrastats")
            if teg:
                res = subprocess.run(
                    [teg, "--interval", "100", "--count", "1"],
                    capture_output=True,
                    text=True,
                )
                profile["jetson"] = {"raw": res.stdout.strip()}

        return profile
    except Exception as e:
        return {"error": str(e)}
