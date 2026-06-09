#!/usr/bin/env python3
import json
import os
import subprocess
import sys

# Color formatting helpers
GREEN = "\033[1;32m"
RED = "\033[1;31m"
YELLOW = "\033[1;33m"
CYAN = "\033[1;36m"
BOLD = "\033[1m"
RESET = "\033[0m"

# Topological order of updates based on submodule dependencies
TOPOLOGICAL_ORDER = [
    "nix-secrets",  # No dependencies
    "nix-devshells",  # No local dependencies
    "nix-hardware",  # Depends on nix-devshells
    "nix-packages",  # Depends on nix-devshells
    "nix-templates",  # Depends on nix-devshells
    "nix-presets",  # Depends on nix-devshells, nix-packages
    "nix-config",  # Depends on presets, packages, hardware, devshells, secrets
]


def run_cmd(args, cwd=None, capture=False):
    """Helper to run a system command."""
    try:
        res = subprocess.run(
            args,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            text=True,
            cwd=cwd,
            check=True,
        )
        return True, res.stdout.strip() if capture else ""
    except subprocess.CalledProcessError as e:
        err = e.stderr.strip() if capture and e.stderr else str(e)
        return False, err


def is_repo_dirty(path):
    """Checks if a git repository has any uncommitted changes (excluding flake.lock)."""
    # Check status of tracked files excluding flake.lock
    success, stdout = run_cmd(["git", "status", "--porcelain"], cwd=path, capture=True)
    if not success:
        return True  # Default to dirty on error

    lines = [line.strip() for line in stdout.split("\n") if line.strip()]
    other_changes = [line for line in lines if not line.endswith("flake.lock")]
    return len(other_changes) > 0


def get_git_head(path):
    success, stdout = run_cmd(["git", "rev-parse", "HEAD"], cwd=path, capture=True)
    return stdout[:8] if success else "unknown"


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)

    print(f"{BOLD}{CYAN}🔄 Topological Workspace Lockfile Sync...{RESET}\n")

    # 1. Pre-check: Ensure no submodules have other uncommitted changes
    dirty_repos = []
    for sub in TOPOLOGICAL_ORDER:
        sub_path = os.path.join(root_dir, sub)
        if os.path.exists(sub_path) and is_repo_dirty(sub_path):
            dirty_repos.append(sub)

    if dirty_repos:
        print(
            f"{RED}❌ Cannot perform sync. The following submodules have other uncommitted changes:{RESET}"
        )
        for r in dirty_repos:
            print(f"  • {BOLD}{r}{RESET}")
        print(
            f'\nPlease stash or commit these changes first using {BOLD}just git::save "your message"{RESET}.'
        )
        sys.exit(1)

    print("🟢 All submodules are clean of non-lockfile changes. Proceeding...\n")

    # 2. Update submodules in topological order
    for sub in TOPOLOGICAL_ORDER:
        sub_path = os.path.join(root_dir, sub)
        if not os.path.exists(sub_path) or not os.path.exists(
            os.path.join(sub_path, "flake.nix")
        ):
            continue

        print(f"{BOLD}Updating {CYAN}{sub}{RESET}...")

        # Read the inputs of the submodule to determine overrides
        lock_path = os.path.join(sub_path, "flake.lock")
        overrides = []
        if os.path.exists(lock_path):
            try:
                with open(lock_path, "r") as f:
                    data = json.load(f)
                inputs = data.get("nodes", {}).get("root", {}).get("inputs", {}).keys()
                for dep in TOPOLOGICAL_ORDER:
                    if dep in inputs:
                        dep_path = os.path.join(root_dir, dep)
                        overrides.extend(
                            ["--override-input", dep, f"git+file://{dep_path}"]
                        )
            except Exception as e:
                print(
                    f"  {YELLOW}Warning: Failed to parse flake.lock for overrides in {sub}: {e}{RESET}"
                )

        # Run nix flake update
        cmd = ["nix", "flake", "update", "--flake", f"./{sub}"] + overrides
        success, err = run_cmd(cmd, cwd=root_dir, capture=True)
        if not success:
            print(f"  {RED}❌ Update failed: {err}{RESET}")
            sys.exit(1)

        # Check if flake.lock was modified
        success, status = run_cmd(
            ["git", "status", "--porcelain", "flake.lock"], cwd=sub_path, capture=True
        )
        if success and status.strip():
            print(f"  📝 {YELLOW}flake.lock updated. Committing change...{RESET}")
            # Stage and commit flake.lock in the submodule
            run_cmd(["git", "add", "flake.lock"], cwd=sub_path)
            # Use pre-commit skip if present to avoid hook loops
            success, _ = run_cmd(
                [
                    "git",
                    "commit",
                    "-m",
                    "chore: auto-update lockfile",
                    "--no-verify",
                    "--no-gpg-sign",
                ],
                cwd=sub_path,
                capture=True,
            )
            if success:
                print(
                    f"  ✅ Committed new state at {BOLD}{get_git_head(sub_path)}{RESET}"
                )
            else:
                print(f"  {RED}❌ Failed to commit lockfile update in {sub}{RESET}")
                sys.exit(1)
        else:
            print(
                f"  🟢 {GREEN}Already in sync at {BOLD}{get_git_head(sub_path)}{RESET}"
            )

    # 3. Update root flake.lock
    print(f"\n{BOLD}Updating root {CYAN}flake.lock{RESET}...")
    overrides = []
    for dep in TOPOLOGICAL_ORDER:
        dep_path = os.path.join(root_dir, dep)
        overrides.extend(["--override-input", dep, f"git+file://{dep_path}"])

    cmd = ["nix", "flake", "update"] + overrides
    success, err = run_cmd(cmd, cwd=root_dir, capture=True)
    if not success:
        print(f"  {RED}❌ Root update failed: {err}{RESET}")
        sys.exit(1)

    success, status = run_cmd(
        ["git", "status", "--porcelain", "flake.lock"], cwd=root_dir, capture=True
    )
    if success and status.strip():
        print(f"  📝 {YELLOW}Root flake.lock updated. Staging change...{RESET}")
        run_cmd(["git", "add", "flake.lock"], cwd=root_dir)

        # Stage the updated submodule commits in the root repo
        for sub in TOPOLOGICAL_ORDER:
            run_cmd(["git", "add", sub], cwd=root_dir)

        print(f"  {GREEN}Workspace root lockfile and submodule pointers staged!{RESET}")
    else:
        print(f"  🟢 {GREEN}Root lockfile already in sync!{RESET}")

    print(f"\n✨ {BOLD}{GREEN}Topological lockfile sync complete!{RESET}")
    print("To save the updated state in the root repository, run:")
    print(f'  {BOLD}git commit -m "chore: update flake lockfiles"{RESET}')


if __name__ == "__main__":
    main()
