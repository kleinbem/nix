#!/usr/bin/env python3
# SOURCE OF TRUTH: scripts/check_lock.py
import fcntl, os, sys

def main():
    lock_file = "/tmp/workspace-just.lock"
    if not os.path.exists(lock_file):
        print("✅ No active workspace lock found.")
        sys.exit(0)
    try:
        with open(lock_file, "r") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print("✅ Lock file exists but is NOT held by any active process.")
    except (IOError, OSError):
        # The lock is held. We can try to find the PID if we wrote it, 
        # but flock usually doesn't store the PID in the file.
        # However, we can use 'ps' to see who is running 'just'.
        print("🕵️ Workspace is LOCKED. Active tasks:")
        os.system("ps -eo pid,user,start,command | grep -E 'just|nixos-rebuild|nh os' | grep -v grep")
    except Exception as e:
        print(f"❌ Error checking lock: {e}")

if __name__ == "__main__":
    main()
