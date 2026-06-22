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

    print(f"{BOLD}{CYAN}🔄 Topological Workspace Lockfile Sync...{RESET}")
    print(
        f"{CYAN}📌 Local-only: re-pins sub-flake inputs to local HEADs."
        f" Upstream bumps (ghostty, rust-overlay, openclaw, nixpkgs, …) are"
        f" CI-only via lockfile-autopilot PRs.{RESET}"
    )
    print(
        f"{YELLOW}   To bump upstream manually (rare): cd <sub> && nix flake update{RESET}\n"
    )

    # 1. Pre-check: Ensure no sub-flake has other uncommitted changes
    dirty_repos = []
    for sub in TOPOLOGICAL_ORDER:
        sub_path = os.path.join(root_dir, sub)
        if os.path.exists(sub_path) and is_repo_dirty(sub_path):
            dirty_repos.append(sub)

    if dirty_repos:
        print(
            f"{RED}❌ Cannot perform sync. The following sub-flakes have other uncommitted changes:{RESET}"
        )
        for r in dirty_repos:
            print(f"  • {BOLD}{r}{RESET}")
        print(
            f'\nPlease commit these changes first using {BOLD}just jj::save-all "your message"{RESET}.'
        )
        sys.exit(1)

    print("🟢 All sub-flakes are clean of non-lockfile changes. Proceeding...\n")

    # 2. Update sub-flakes in topological order
    for sub in TOPOLOGICAL_ORDER:
        sub_path = os.path.join(root_dir, sub)
        if not os.path.exists(sub_path) or not os.path.exists(
            os.path.join(sub_path, "flake.nix")
        ):
            continue

        print(f"{BOLD}Updating {CYAN}{sub}{RESET}...")

        # Read the inputs of the submodule
        lock_path = os.path.join(sub_path, "flake.lock")
        local_deps = []
        if os.path.exists(lock_path):
            try:
                with open(lock_path, "r") as f:
                    data = json.load(f)
                inputs = data.get("nodes", {}).get("root", {}).get("inputs", {}).keys()
                # Only sub-flake inputs that live in this workspace count as
                # "local deps" — those are the ones we re-pin to local HEADs.
                local_deps = [dep for dep in TOPOLOGICAL_ORDER if dep in inputs]
            except Exception as e:
                print(
                    f"  {YELLOW}Warning: Failed to parse flake.lock in {sub}: {e}{RESET}"
                )

        # No local sub-flake deps → nothing to re-pin → skip entirely.
        # External inputs (ghostty, rust-overlay, openclaw, nixpkgs, …) are
        # CI's responsibility — lockfile-autopilot opens PRs for those.
        if not local_deps:
            print(
                f"  ⏭  {CYAN}No local sub-flake deps — skipping"
                f" (upstream bumps via CI PR).{RESET}"
            )
            continue

        # Pass local dep names as positional args so `nix flake update` only
        # refreshes those specific inputs. External inputs keep their pins.
        cmd = ["nix", "flake", "update"] + local_deps + ["--flake", f"./{sub}"]
        for dep in local_deps:
            dep_path = os.path.join(root_dir, dep)
            cmd += ["--override-input", dep, f"git+file://{dep_path}"]

        success, err = run_cmd(cmd, cwd=root_dir, capture=True)
        if not success:
            print(f"  {RED}❌ Update failed: {err}{RESET}")
            sys.exit(1)

        # Check if flake.lock was modified
        success, status = run_cmd(
            ["git", "status", "--porcelain", "flake.lock"], cwd=sub_path, capture=True
        )
        if success and status.strip():
            print(f"  📝 {YELLOW}flake.lock updated. Staging (not committing).{RESET}")
            # Stage only — the human commits via `just jj::save-all` or
            # `jj describe` when convenient. Auto-committing here triggered
            # one YubiKey touch per sub-flake during `just apply` (signing
            # under non-interactive subprocess context), which is more
            # friction than it's worth for purely-machine-generated commits.
            run_cmd(["git", "add", "flake.lock"], cwd=sub_path)
            print(f"  ✅ Staged in {BOLD}{sub}{RESET} (commit when ready)")
        else:
            print(
                f"  🟢 {GREEN}Already in sync at {BOLD}{get_git_head(sub_path)}{RESET}"
            )

    # The meta dir no longer has a flake.nix (deleted 2026-06-22 — nix-config
    # is the root flake). Each sub-flake's lockfile is the source of truth
    # for its own inputs; the topological sweep above already handles the
    # cross-sub-flake propagation.
    print(f"\n✨ {BOLD}{GREEN}Topological lockfile sync complete!{RESET}")
    print("To save the updated state in the root repository, run:")
    print(f'  {BOLD}jj describe -m "chore: update flake lockfiles"{RESET}')


if __name__ == "__main__":
    main()
