import os
import glob
import json

BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")

def find_missing():
    print(f"🔍 Analyzing {BRAIN_DIR}...")
    all_convs = os.listdir(BRAIN_DIR)
    missing = []
    
    for conv_id in all_convs:
        path = os.path.join(BRAIN_DIR, conv_id)
        if not os.path.isdir(path):
            continue
            
        # Check for metadata
        has_meta = len(glob.glob(os.path.join(path, "*.metadata.json"))) > 0
        
        # Check for logs
        overview_path = os.path.join(path, ".system_generated", "logs", "overview.txt")
        has_logs = os.path.exists(overview_path)
        
        if has_logs and not has_meta:
            missing.append(conv_id)
            
    print(f"✅ Found {len(missing)} conversations with logs but NO metadata.")
    for cid in missing[:10]: # Show first 10
        print(f" - {cid}")
    if len(missing) > 10:
        print(f" ... and {len(missing) - 10} more.")

if __name__ == "__main__":
    find_missing()
