import os
import json
from datetime import datetime
from .core import mcp, DEFAULT_FLAKE_PATH, STATE_FILE


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
