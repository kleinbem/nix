# --- Shared Variables ---

# Get the absolute path to the project root (parent of .just directory)
ROOT := parent_directory(justfile_directory())

# Identify nix-* and github-config repositories in the root (trimmed of any extra whitespace)
REPOS := shell("nix eval --raw --file " + ROOT + "/repos.nix --apply 'rs: builtins.concatStringsSep \" \" (builtins.attrNames rs)' 2>/dev/null || echo 'nix-config nix-presets nix-hardware nix-packages nix-devshells nix-templates nix-secrets github-config'")

# Use | as the sed delimiter to avoid conflict with the forward slashes in the ROOT path
OVERRIDES := shell("echo '" + REPOS + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + ROOT + "/\\1|g'")
KEEP := "3"
TIMER := "time "
LOCK_FILE := "/tmp/workspace-just.lock"
# Non-blocking lock command wrapper for better error messages
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
