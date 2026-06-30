import subprocess
from .core import mcp, DEFAULT_FLAKE_PATH


@mcp.tool()
def run_jj_command(args: list = ["status"]):
    """
    Run a jujutsu (jj) command in the workspace.
    Useful args: ['status'], ['log', '-T', 'builtin_log_compact'], ['diff']
    Do not include 'jj' itself in the args list.
    """
    try:
        cmd = ["jj"] + args
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
def jj_status():
    """Get the current Jujutsu (jj) working copy status, including conflicts and changed files."""
    try:
        result = subprocess.run(
            ["jj", "--no-pager", "status"],
            capture_output=True,
            text=True,
            cwd=DEFAULT_FLAKE_PATH,
        )
        return result.stdout if result.returncode == 0 else f"Error: {result.stderr}"
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def jj_diff(revision: str = "@"):
    """Get the code diff for a specific Jujutsu revision. Defaults to the working copy (@)."""
    try:
        result = subprocess.run(
            ["jj", "--no-pager", "diff", "-r", revision, "--git"],
            capture_output=True,
            text=True,
            cwd=DEFAULT_FLAKE_PATH,
        )
        return result.stdout if result.returncode == 0 else f"Error: {result.stderr}"
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def jj_commit(message: str):
    """Set the commit description for the current Jujutsu working copy (@)."""
    try:
        result = subprocess.run(
            ["jj", "--no-pager", "describe", "-m", message],
            capture_output=True,
            text=True,
            cwd=DEFAULT_FLAKE_PATH,
        )
        return result.stdout if result.returncode == 0 else f"Error: {result.stderr}"
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def jj_log(limit: int = 10):
    """Get a structured list of recent Jujutsu revisions."""
    try:
        template = 'commit_id.short() ++ " [" ++ change_id.short() ++ "] " ++ author.name() ++ " - " ++ description.first_line() ++ "\\n"'
        result = subprocess.run(
            ["jj", "--no-pager", "log", "-n", str(limit), "-T", template, "--no-graph"],
            capture_output=True,
            text=True,
            cwd=DEFAULT_FLAKE_PATH,
        )
        if result.returncode != 0:
            return f"Error: {result.stderr}"

        lines = result.stdout.strip().split("\\n")
        return [line for line in lines if line]
    except Exception as e:
        return {"error": str(e)}
