#!/usr/bin/env python3
# SOURCE OF TRUTH: scripts/workspace-mcp.py
import os
import json
import subprocess
import sqlite3
import shutil
import requests
from datetime import datetime, timedelta
from mcp.server.fastmcp import FastMCP

# Google API Imports
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

# ATLAS Infrastructure AI - Autonomous Management V3.3 (Mesh & Sync)

mcp = FastMCP("workspace-atlas")

# --- PATHS ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FLAKE_PATH = os.path.dirname(SCRIPT_DIR)
VAULT_PATH = os.path.join(os.path.expanduser("~"), "Documents/Notes")
FIREFOX_PATH = os.path.expanduser("~/.mozilla/firefox")
KNOWLEDGE_DIR = os.path.join(DEFAULT_FLAKE_PATH, ".agent/knowledge")
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/drive.readonly",
]
GOOGLE_TOKEN_PATH = os.path.join(DEFAULT_FLAKE_PATH, "nix-secrets/google_token.json")
GOOGLE_CREDS_PATH = os.path.join(
    DEFAULT_FLAKE_PATH, "nix-secrets/google_credentials.json"
)
STATE_FILE = os.path.join(DEFAULT_FLAKE_PATH, "scratch/workspace_state.json")
PAPERLESS_TOKEN_PATH = os.path.join(
    DEFAULT_FLAKE_PATH, "nix-secrets/paperless_token.txt"
)

_INVENTORY_CACHE = None


def _get_inventory_cached():
    global _INVENTORY_CACHE
    if _INVENTORY_CACHE is not None:
        return _INVENTORY_CACHE
    try:
        inv_path = os.path.join(DEFAULT_FLAKE_PATH, "nix-config/inventory.nix")
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


def _get_paperless_url():
    inv = _get_inventory_cached()
    try:
        node = inv.get("network", {}).get("nodes", {}).get("paperless", {})
        ip = node.get("ip", "10.85.47.131")
        port = node.get("port", 28981)
        return f"http://{ip}:{port}"
    except Exception:
        return "http://10.85.47.131:28981"


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


# --- TOOLS ---


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


@mcp.tool()
def firefox_search(query: str, profile: str = "standard"):
    """Search Firefox history for a keyword in a specific profile (standard, laboratory, temp)."""
    try:
        profiles = [d for d in os.listdir(FIREFOX_PATH) if d.endswith(f".{profile}")]
        if not profiles:
            return f"Error: Profile {profile} not found."
        db_path = os.path.join(FIREFOX_PATH, profiles[0], "places.sqlite")
        if not os.path.exists(db_path):
            return f"Error: Places database not found for {profile}."
        temp_db = f"/tmp/firefox_{profile}_search.sqlite"
        shutil.copy2(db_path, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        sql = "SELECT title, url FROM moz_places WHERE (title LIKE ? OR url LIKE ?) ORDER BY last_visit_date DESC LIMIT 10"
        cursor.execute(sql, (f"%{query}%", f"%{query}%"))
        results = cursor.fetchall()
        conn.close()
        os.remove(temp_db)
        return [{"title": r[0], "url": r[1]} for r in results]
    except Exception as e:
        return str(e)


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
def get_fleet_status():
    """Check connectivity and status of all hosts in the inventory using Colmena/NetBird."""
    results = {}
    try:
        # Get inventory first
        inventory = get_inventory_summary()
        if "error" in inventory:
            return inventory

        # Check NetBird status for mesh connectivity
        nb = netbird_status()
        peers = {}
        if isinstance(nb, dict) and "peers" in nb:
            for p in nb["peers"]:
                peers[p.get("hostname", "unknown")] = p.get("status", "offline")

        for host, data in inventory.items():
            results[host] = {
                "ip": data.get("ipv4", "unknown"),
                "mesh_status": peers.get(host, "offline"),
                "tags": data.get("tags", []),
            }
    except Exception as e:
        return {"error": str(e)}
    return results


@mcp.tool()
def list_skills():
    """List all available agent workflows (skills) in the workspace."""
    workflow_dir = os.path.join(DEFAULT_FLAKE_PATH, ".agent/workflows")
    try:
        if not os.path.exists(workflow_dir):
            return []
        files = [f for f in os.listdir(workflow_dir) if f.endswith(".md")]
        skills = []
        for f in files:
            with open(os.path.join(workflow_dir, f), "r") as file:
                content = file.read()
                # Simple extraction of description from frontmatter
                desc = "No description"
                if "description:" in content:
                    desc = (
                        content.split("description:")[1]
                        .split("\n")[0]
                        .strip()
                        .strip('"')
                    )
                skills.append(
                    {
                        "name": f.replace(".md", ""),
                        "description": desc,
                        "path": os.path.join(workflow_dir, f),
                    }
                )
        return skills
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def is_task_running():
    """
    Check if a long-running workspace task (like apply or build) is currently active.
    Returns True if locked, False otherwise.
    """
    lock_file = "/tmp/workspace-just.lock"
    if not os.path.exists(lock_file):
        return False

    # Try to acquire the lock in non-blocking mode to see if it's held
    import fcntl

    try:
        with open(lock_file, "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False  # We got the lock, so no one else was holding it
    except (IOError, OSError):
        return True  # Someone else has it
    except Exception as e:
        return {"error": str(e)}


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
def run_just_recipe(recipe: str, args: list = []):
    """Run a just recipe from the workspace."""
    try:
        cmd = ["just", recipe] + args
        result = subprocess.run(
            cmd, capture_output=True, text=True, cwd=DEFAULT_FLAKE_PATH
        )
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "exit_code": result.returncode,
        }
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def update_todo(task: str, status: str = "done"):
    """Add or update a task in TODO.md."""
    try:
        todo_path = os.path.join(DEFAULT_FLAKE_PATH, "TODO.md")
        if not os.path.exists(todo_path):
            with open(todo_path, "w") as f:
                f.write("# Project Tasks\n\n")
        with open(todo_path, "r") as f:
            content = f.read()
        mark = "[x]" if status == "done" else "[ ]"
        new_line = f"- {mark} {task}\n"
        if task not in content:
            with open(todo_path, "a") as f:
                f.write(new_line)
        else:
            old_mark = "[ ]" if status == "done" else "[x]"
            content = content.replace(f"- {old_mark} {task}", new_line)
            with open(todo_path, "w") as f:
                f.write(content)
        return f"Task updated: {task}"
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def distill_knowledge(
    title: str, summary: str, context: str, status: str = "active", tags: list = []
):
    """
    Create a new Knowledge Item (KI) in the workspace.
    Used to 'remember' architectural decisions, bug fixes, or complex configurations.
    Status can be: active, experimental, deprecated, or obsolete.
    """
    try:
        os.makedirs(KNOWLEDGE_DIR, exist_ok=True)
        filename = title.lower().replace(" ", "_").replace("/", "_") + ".md"
        filepath = os.path.join(KNOWLEDGE_DIR, filename)

        content = f"""# {title}
*Created: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}*
*Status: {status}*

## Summary
{summary}

## Context / Implementation
{context}

## Tags
{", ".join(tags)}
"""
        with open(filepath, "w") as f:
            f.write(content)

        # Link to obsidian if the script exists
        linker = os.path.join(DEFAULT_FLAKE_PATH, "scripts/link-docs-to-obsidian.sh")
        if os.path.exists(linker):
            subprocess.run([linker], capture_output=True)

        return f"Knowledge Item created: {filepath}"
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def analyze_logs(unit: str = None, machine: str = None, lines: int = 50):
    """
    Fetch and analyze recent logs using ai-logs.py.
    Provides a high-level assessment of any errors found.
    """
    try:
        cmd = [
            "python3",
            os.path.join(DEFAULT_FLAKE_PATH, "scripts/ai-logs.py"),
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
def semantic_search(query: str):
    """
    Search the Obsidian vault using semantic similarity (embeddings).
    If Ollama is online, it uses vector math to find the closest matches.
    """
    try:
        index_path = os.path.join(DEFAULT_FLAKE_PATH, "scratch/semantic_index.json")
        if not os.path.exists(index_path):
            return "Error: Semantic index not found. Run reindex_vault first."

        with open(index_path, "r") as f:
            index = json.load(f)

        # Try to get query embedding
        query_embedding = None
        ai_info = _get_ai_base_url()
        if ai_info:
            base_url = ai_info["url"]
            engine_type = ai_info["type"]
            try:
                if engine_type == "ollama":
                    resp = requests.post(
                        f"{base_url}/api/embeddings",
                        json={"model": "nomic-embed-text", "prompt": query},
                        timeout=3,
                    )
                else:  # llama-cpp
                    resp = requests.post(
                        f"{base_url}/embedding", json={"content": query}, timeout=3
                    )

                if resp.status_code == 200:
                    # Ollama returns 'embedding', llama.cpp returns 'embedding' inside a list or directly
                    data = resp.json()
                    query_embedding = data.get("embedding")
            except Exception:
                pass

        def dot_product(v1, v2):
            return sum(x * y for x, y in zip(v1, v2))

        def magnitude(v):
            return sum(x * x for x in v) ** 0.5

        def cosine_similarity(v1, v2):
            if not v1 or not v2:
                return 0
            m1, m2 = magnitude(v1), magnitude(v2)
            if m1 == 0 or m2 == 0:
                return 0
            return dot_product(v1, v2) / (m1 * m2)

        results = []
        for doc in index:
            score = 0
            if query_embedding and doc.get("embedding"):
                score = cosine_similarity(query_embedding, doc["embedding"])
            else:
                # Fallback to simple keyword overlap if no embeddings
                if (
                    query.lower() in doc["title"].lower()
                    or query.lower() in doc["excerpt"].lower()
                ):
                    score = 0.5  # Default score for keyword match

            if score > 0.1:
                results.append(
                    {
                        "title": doc["title"],
                        "path": doc["path"],
                        "excerpt": doc["excerpt"],
                        "score": round(score, 3),
                    }
                )

        # Sort by score
        results.sort(key=lambda x: x["score"], reverse=True)
        return results[:5] if results else "No matches found."
    except Exception as e:
        return {"error": str(e)}


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


@mcp.tool()
def get_security_audit_summary():
    """
    Read and summarize the latest Lynis security audit report.
    Provides a count of warnings and suggestions for hardening.
    """
    report_path = "/var/log/lynis-report.txt"
    try:
        if not os.path.exists(report_path):
            return "Security audit report not found. Run 'just maintenance::audit' to generate it."

        with open(report_path, "r") as f:
            lines = f.readlines()

        summary = {"warnings": [], "suggestions": [], "hardening_index": "Unknown"}

        for line in lines:
            if "Warning:" in line:
                summary["warnings"].append(line.split("Warning:")[1].strip())
            elif "Suggestion:" in line:
                summary["suggestions"].append(line.split("Suggestion:")[1].strip())
            elif "Hardening index" in line:
                # Format:  - Hardening index : 84 [###########         ]
                parts = line.split(":")
                if len(parts) > 1:
                    summary["hardening_index"] = parts[1].split("[")[0].strip()

        return {
            "status": "Audit Complete",
            "hardening_index": summary["hardening_index"],
            "warning_count": len(summary["warnings"]),
            "suggestion_count": len(summary["suggestions"]),
            "top_warnings": summary["warnings"][:5],
            "top_suggestions": summary["suggestions"][:5],
        }
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def reindex_vault():
    """
    Run the semantic indexer to refresh the vault index.
    """
    try:
        cmd = [
            "python3",
            os.path.join(DEFAULT_FLAKE_PATH, "scripts/workspace-indexer.py"),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return {"stdout": result.stdout, "stderr": result.stderr}
    except Exception as e:
        return {"error": str(e)}


def _get_google_creds():
    """Helper to handle Google OAuth2 flow."""
    creds = None
    if os.path.exists(GOOGLE_TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(GOOGLE_TOKEN_PATH, GOOGLE_SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(GOOGLE_CREDS_PATH):
                raise Exception(
                    f"Google credentials not found at {GOOGLE_CREDS_PATH}. Please download credentials.json from Google Cloud Console."
                )
            flow = InstalledAppFlow.from_client_secrets_file(
                GOOGLE_CREDS_PATH, GOOGLE_SCOPES
            )
            creds = flow.run_local_server(port=0)

        with open(GOOGLE_TOKEN_PATH, "w") as token:
            token.write(creds.to_json())
    return creds


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
        except Exception:
            pass

        # Check Health Sink from ai-logs.py
        health_status = "Unknown"
        sink_path = os.path.join(DEFAULT_FLAKE_PATH, "scratch/ai-health.json")
        if os.path.exists(sink_path):
            with open(sink_path, "r") as f:
                sink_data = json.load(f)
                health_status = sink_data.get("status", "Unknown")
                # If degraded, trigger a refresh in the background
                if health_status == "Degraded":
                    subprocess.Popen(
                        [
                            "python3",
                            os.path.join(DEFAULT_FLAKE_PATH, "scripts/ai-logs.py"),
                            "--sink",
                        ]
                    )
        else:
            # First time? Run it once.
            subprocess.Popen(
                [
                    "python3",
                    os.path.join(DEFAULT_FLAKE_PATH, "scripts/ai-logs.py"),
                    "--sink",
                ]
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
def get_calendar_events(days: int = 7):
    """
    Fetch upcoming events from Google Calendar.
    Used to check for meetings or busy periods before scheduling maintenance.
    """
    try:
        creds = _get_google_creds()
        service = build("calendar", "v3", credentials=creds)

        now = datetime.utcnow().isoformat() + "Z"
        end_time = (datetime.utcnow() + timedelta(days=days)).isoformat() + "Z"

        events_result = (
            service.events()
            .list(
                calendarId="primary",
                timeMin=now,
                timeMax=end_time,
                singleEvents=True,
                orderBy="startTime",
            )
            .execute()
        )
        events = events_result.get("items", [])

        if not events:
            return "No upcoming events found."

        summary = []
        for event in events:
            start = event["start"].get("dateTime", event["start"].get("date"))
            summary.append(
                {
                    "start": start,
                    "summary": event.get("summary", "No Title"),
                    "description": event.get("description", ""),
                }
            )
        return summary
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


# Google Drive tools (search_drive_docs, read_drive_doc) removed — superseded by
# Anthropic's official `claude_ai_Google_Drive` MCP, which provides equivalent
# capability via `mcp__claude_ai_Google_Drive__*` tools. Keep `_get_google_creds`
# in place since `get_calendar_events` still uses it.


# --- PAPERLESS TOOLS ---


def _get_paperless_headers():
    """Helper to load Paperless API token."""
    if not os.path.exists(PAPERLESS_TOKEN_PATH):
        return None
    try:
        with open(PAPERLESS_TOKEN_PATH, "r") as f:
            token = f.read().strip()
        return {"Authorization": f"Token {token}"}
    except Exception:
        return None


@mcp.tool()
def search_paperless(query: str):
    """Search for documents in Paperless-ngx matching a query."""
    headers = _get_paperless_headers()
    if not headers:
        return "Error: Paperless token not found. Add it to nix-secrets/paperless_token.txt"

    try:
        paperless_url = _get_paperless_url()
        resp = requests.get(
            f"{paperless_url}/api/documents/?query={query}", headers=headers, timeout=5
        )
        if resp.status_code == 200:
            results = resp.json().get("results", [])
            return [
                {"id": d["id"], "title": d["title"], "created": d["created"]}
                for d in results[:10]
            ]
        return f"Error: Paperless API returned {resp.status_code}"
    except Exception as e:
        return str(e)


@mcp.tool()
def get_paperless_document(doc_id: int):
    """Get the full details and OCR text content of a Paperless document."""
    headers = _get_paperless_headers()
    if not headers:
        return "Error: Paperless token not found."

    try:
        paperless_url = _get_paperless_url()
        resp = requests.get(
            f"{paperless_url}/api/documents/{doc_id}/", headers=headers, timeout=5
        )
        if resp.status_code != 200:
            return f"Error: Could not find document {doc_id}"
        doc = resp.json()

        return {
            "title": doc.get("title"),
            "content": doc.get("content", "No text content available."),
            "date": doc.get("created"),
            "tags": doc.get("tags"),
            "correspondent": doc.get("correspondent"),
        }
    except Exception as e:
        return str(e)


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
def analyze_nix_closure(attr_path: str):
    """Calculate closure size and dependency count for a Nix attribute."""
    try:
        cmd = ["nix", "path-info", "-Ssh", f".#{attr_path}", "--impure"]
        res = subprocess.run(
            cmd, capture_output=True, text=True, cwd=DEFAULT_FLAKE_PATH
        )
        if res.returncode != 0:
            return {"error": res.stderr}
        return {"summary": res.stdout.strip()}
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def checkpoint_workspace_state(summary: str, goals: list, blockers: list = []):
    """Save a snapshot of the current project state for context recovery."""
    try:
        state = {
            "timestamp": datetime.now().isoformat(),
            "summary": summary,
            "goals": goals,
            "blockers": blockers,
        }
        with open(STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)
        return "Workspace state checkpointed."
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def get_workspace_state():
    """Retrieve the last saved workspace state."""
    try:
        if not os.path.exists(STATE_FILE):
            return "No state found."
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def check_binary_cache(pkg_name: str):
    """Check if a package is available in the Nix binary cache."""
    try:
        # Check cache.nixos.org
        # This is tricky because path-info needs a store path.
        # A better way is to try to substitute it.
        # Let's use a simpler check: try to find it in the public cache via nix search or similar
        res = subprocess.run(
            ["nix", "search", "nixpkgs", pkg_name, "--json"],
            capture_output=True,
            text=True,
        )
        return json.loads(res.stdout)
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def manage_skill_progress(
    skill_name: str, step_index: int = None, status: str = "view"
):
    """
    Manage progress through a workspace skill.
    Status: view, complete, reset.
    """
    progress_file = os.path.join(DEFAULT_FLAKE_PATH, "scratch/skill_progress.json")
    try:
        progress = {}
        if os.path.exists(progress_file):
            with open(progress_file, "r") as f:
                progress = json.load(f)

        if skill_name not in progress:
            progress[skill_name] = {
                "completed_steps": [],
                "last_updated": datetime.now().isoformat(),
            }

        if status == "complete" and step_index is not None:
            if step_index not in progress[skill_name]["completed_steps"]:
                progress[skill_name]["completed_steps"].append(step_index)
                progress[skill_name]["last_updated"] = datetime.now().isoformat()
        elif status == "reset":
            progress[skill_name]["completed_steps"] = []

        with open(progress_file, "w") as f:
            json.dump(progress, f, indent=2)

        return progress[skill_name]
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


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        # Simple CLI mode for manual testing
        tool_name = sys.argv[1]
        if tool_name == "get_calendar_events":
            print(json.dumps(get_calendar_events(), indent=2))
        else:
            print(f"Unknown tool: {tool_name}")
    else:
        mcp.run()
