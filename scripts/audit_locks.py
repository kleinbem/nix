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

def get_git_head(path):
    """Returns the current git HEAD commit hash for a directory, or None if error."""
    try:
        res = subprocess.run(
            ["git", "-C", path, "rev-parse", "HEAD"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        return res.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def find_submodules(root):
    """Finds all submodules defined in .gitmodules and returns a dict mapping path -> current HEAD."""
    submodules = {}
    gitmodules_path = os.path.join(root, ".gitmodules")
    if not os.path.exists(gitmodules_path):
        return submodules

    try:
        # Read .gitmodules to get paths
        with open(gitmodules_path, "r") as f:
            lines = f.readlines()
        
        current_path = None
        for line in lines:
            line = line.strip()
            if line.startswith("[submodule"):
                current_path = None
            elif line.startswith("path ="):
                current_path = line.split("=")[1].strip()
                if current_path:
                    abs_path = os.path.join(root, current_path)
                    head_commit = get_git_head(abs_path)
                    if head_commit:
                        submodules[current_path] = {
                            "name": os.path.basename(current_path),
                            "abs_path": abs_path,
                            "head": head_commit
                        }
    except Exception as e:
        print(f"{RED}Error reading submodules: {e}{RESET}")
    
    return submodules

def find_lock_files(root):
    """Finds all flake.lock files recursively under root, ignoring node_modules, .git, etc."""
    lock_files = []
    for dirpath, _, filenames in os.walk(root):
        # Skip common directories to avoid slow scans
        if any(part in dirpath.split(os.sep) for part in [".git", "node_modules", ".devenv", ".tools"]):
            continue
        for f in filenames:
            if f == "flake.lock":
                lock_files.append(os.path.join(dirpath, f))
    return sorted(lock_files)

def audit_lock_file(lock_path, submodules, root):
    """Audits a single flake.lock file and checks if any submodule is out of sync."""
    rel_lock_path = os.path.relpath(lock_path, root)
    
    try:
        with open(lock_path, "r") as f:
            data = json.load(f)
    except Exception as e:
        print(f"  {RED}❌ Failed to parse {rel_lock_path}: {e}{RESET}")
        return False, []

    nodes = data.get("nodes", {})
    mismatches = []
    
    # We want to check inputs that match our submodules.
    # We look at the top-level inputs (defined in the "root" node) to see what keys they map to,
    # as well as any other node that might be representing a submodule input.
    root_inputs = nodes.get("root", {}).get("inputs", {})
    
    # Map submodule names to the keys they are locked under
    for sub_path, sub_info in submodules.items():
        sub_name = sub_info["name"]
        sub_head = sub_info["head"]
        
        # Check if root_inputs maps this submodule to a specific node key
        node_key = root_inputs.get(sub_name)
        if not node_key and sub_name in nodes:
            node_key = sub_name
            
        # If we have a node key, inspect it
        if node_key and node_key in nodes:
            node_data = nodes[node_key]
            locked = node_data.get("locked")
            if locked and "rev" in locked:
                locked_rev = locked["rev"]
                if locked_rev != sub_head:
                    mismatches.append({
                        "submodule": sub_name,
                        "node_key": node_key,
                        "locked_rev": locked_rev,
                        "local_rev": sub_head
                    })
        else:
            # Let's also scan all nodes to see if this submodule is locked anywhere in the dependency tree
            for key, val in nodes.items():
                # Check if it has a locked repo name matching the submodule name
                locked = val.get("locked", {})
                if locked and locked.get("repo") == sub_name and "rev" in locked:
                    locked_rev = locked["rev"]
                    if locked_rev != sub_head:
                        # Avoid duplicates
                        if not any(m["submodule"] == sub_name and m["node_key"] == key for m in mismatches):
                            mismatches.append({
                                "submodule": sub_name,
                                "node_key": key,
                                "locked_rev": locked_rev,
                                "local_rev": sub_head
                            })

    return True, mismatches

def main():
    # Root of project
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    
    print(f"{BOLD}{CYAN}🔍 Auditing workspace flake.lock files against local submodule commits...{RESET}\n")
    
    # Get current root commit
    root_head = get_git_head(root_dir)
    if root_head:
        print(f"Workspace Root HEAD: {BOLD}{root_head[:8]}{RESET}")
    
    # Get submodules status
    submodules = find_submodules(root_dir)
    if not submodules:
        print(f"{YELLOW}No submodules found.{RESET}")
        sys.exit(0)
        
    print(f"Found {len(submodules)} local submodules:")
    for path, info in submodules.items():
        print(f"  • {BOLD}{info['name']}{RESET} at {BOLD}{info['head'][:8]}{RESET} ({path})")
    print()

    # Find lock files
    lock_files = find_lock_files(root_dir)
    if not lock_files:
        print(f"{YELLOW}No flake.lock files found.{RESET}")
        sys.exit(0)
        
    any_mismatch = False
    
    for lock_path in lock_files:
        rel_path = os.path.relpath(lock_path, root_dir)
        success, mismatches = audit_lock_file(lock_path, submodules, root_dir)
        if not success:
            continue
            
        if not mismatches:
            print(f"🟢 {BOLD}{rel_path}{RESET}: {GREEN}All submodules in sync!{RESET}")
        else:
            print(f"🔴 {BOLD}{rel_path}{RESET}: {RED}{len(mismatches)} out of sync!{RESET}")
            any_mismatch = True
            for m in mismatches:
                print(f"  • {BOLD}{m['submodule']}{RESET} (locked node: {CYAN}{m['node_key']}{RESET})")
                print(f"    🔒 Locked: {RED}{m['locked_rev'][:8]}{RESET}")
                print(f"    💻 Local:  {GREEN}{m['local_rev'][:8]}{RESET}")
    
    print()
    if any_mismatch:
        print(f"{YELLOW}⚠️  Some flake.lock files are out of sync with your local commits!{RESET}")
        print("To update the root lockfile to lock your local submodule commits, run:")
        print(f"  {BOLD}just update-local{RESET}")
        print("To refresh all sub-flake lockfiles to their current submodule commits, run:")
        print(f"  {BOLD}just maintenance::lock-refresh{RESET}")
        print(f"\n{BOLD}Note:{RESET} Make sure to stage and commit your local changes inside submodules first so they have updated git commits.")
        sys.exit(1)
    else:
        print(f"✨ {GREEN}All workspace lockfiles are fully in sync with local submodule HEADs!{RESET}")
        sys.exit(0)

if __name__ == "__main__":
    main()
