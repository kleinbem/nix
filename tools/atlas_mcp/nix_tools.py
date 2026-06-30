import json
import subprocess
from .core import mcp, DEFAULT_FLAKE_PATH


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
def check_binary_cache(pkg_name: str):
    """Check if a package is available in the Nix binary cache."""
    try:
        res = subprocess.run(
            ["nix", "search", "nixpkgs", pkg_name, "--json"],
            capture_output=True,
            text=True,
        )
        return json.loads(res.stdout)
    except Exception as e:
        return {"error": str(e)}
