import os
import json
import requests
import subprocess
from .core import mcp, DEFAULT_FLAKE_PATH, SYSTEMCTL
from .inventory import _get_inventory_cached


def _get_ollama_remote_ip():
    inv = _get_inventory_cached()
    try:
        return (
            inv.get("network", {})
            .get("nodes", {})
            .get("ollama-orin", {})
            .get("ip", "10.85.46.104")
        )
    except Exception:
        return "10.85.46.104"


def _get_ai_base_url():
    """Determine the best AI engine endpoint (Ollama or llama.cpp) to use."""
    ollama_ip = _get_ollama_remote_ip()
    endpoints = [
        "http://localhost:11434",
        f"http://{ollama_ip}:11434",
        "http://10.85.46.126:11434",  # llama-cpp container IP
    ]

    for url in endpoints:
        try:
            # Check for Ollama
            resp = requests.get(f"{url}/api/tags", timeout=0.5)
            if resp.status_code == 200:
                return {"url": url, "type": "ollama"}
        except Exception:
            pass

        try:
            # Check for llama.cpp server
            resp = requests.get(f"{url}/health", timeout=0.5)
            if resp.status_code == 200:
                return {"url": url, "type": "llama-cpp"}
        except Exception:
            pass

    return None


@mcp.tool()
def check_ai_stack_health(target_host: str = "nixos-nvme", fix: bool = False):
    """
    Check health of containers and secrets on a specific host.
    If target_host is 'nixos-nvme' (local), it checks systemd units.
    If fix is True, it attempts to restart failed units.
    """
    results = {"host": target_host, "containers": {}, "secrets": {}, "alerts": []}
    try:
        # Evaluate config to find all containers for this host
        attr_path = f".#nixosConfigurations.{target_host}.config.my.containers"
        eval_cmd = ["nix", "eval", "--json", "--impure", attr_path]
        proc = subprocess.run(
            eval_cmd, capture_output=True, text=True, cwd=DEFAULT_FLAKE_PATH
        )

        if proc.returncode != 0:
            return {
                "error": f"Failed to evaluate containers for {target_host}: {proc.stderr}"
            }

        containers = json.loads(proc.stdout)

        for name, data in containers.items():
            if not data.get("enable", False):
                continue

            status = "unknown"
            if target_host == "nixos-nvme":
                unit = f"container@{name}.service"
                status = subprocess.run(
                    [SYSTEMCTL, "is-active", unit], capture_output=True, text=True
                ).stdout.strip()

                if status != "active" and fix:
                    subprocess.run(["sudo", SYSTEMCTL, "restart", unit])
                    status = subprocess.run(
                        [SYSTEMCTL, "is-active", unit], capture_output=True, text=True
                    ).stdout.strip()
                    results["alerts"].append(
                        f"Restarted container {name}. New status: {status}"
                    )

            results["containers"][name] = {
                "status": status,
                "image": data.get("image", "nixpkgs"),
            }

        # Check for rendered secrets (local only for now)
        if target_host == "nixos-nvme":
            secret_dir = "/run/secrets/rendered"
            if os.path.exists(secret_dir):
                for s in os.listdir(secret_dir):
                    results["secrets"][s] = "Present"
            else:
                results["alerts"].append("Secret render directory missing")

    except Exception as e:
        results["error"] = str(e)
    return results


@mcp.tool()
def manage_ai_services(action: str, service: str = "ollama"):
    """
    Manage local AI services (ollama, vllm).
    Actions: start, stop, restart, status.
    """
    try:
        unit = f"{service}.service"
        if action == "status":
            res = subprocess.run(
                [SYSTEMCTL, "is-active", unit], capture_output=True, text=True
            )
            return f"{service} is {res.stdout.strip()}"

        # Requires sudo, assumes user has passwordless sudo for these units
        subprocess.run(["sudo", SYSTEMCTL, action, unit], check=True)
        return f"Service {service} {action}ed successfully."
    except Exception as e:
        return {"error": str(e)}
