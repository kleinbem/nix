import os
import json
from datetime import datetime
from .core import mcp, DEFAULT_FLAKE_PATH


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
