# --- Shared Variables ---

# Get the absolute path to the project root (parent of this justfile)
ROOT := parent_directory(justfile())

# Identify nix-* repositories in the root (trimmed of any extra whitespace)
REPOS := shell("find " + ROOT + " -maxdepth 1 -name 'nix-*' -type d -printf '%f\n' | xargs echo -n")

# Use | as the sed delimiter to avoid conflict with the forward slashes in the ROOT path
OVERRIDES := shell("echo '" + REPOS + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + ROOT + "/\\1|g'")
KEEP := "3"
TIMER := "time "
LOCK_FILE := "/tmp/workspace-just.lock"
# Non-blocking lock command wrapper for better error messages
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
