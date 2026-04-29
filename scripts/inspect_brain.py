import os
import glob

brain_dir = os.path.expanduser("~/.gemini/antigravity/brain")
target_id = "2cfaed38-079d-4145-b188-c0d1a03edbc0"
target_path = os.path.join(brain_dir, target_id)

print(f"Inspecting: {target_path}")
if os.path.exists(target_path):
    for root, dirs, files in os.walk(target_path):
        level = root.replace(target_path, '').count(os.sep)
        indent = ' ' * 4 * (level)
        print(f"{indent}{os.path.basename(root)}/")
        subindent = ' ' * 4 * (level + 1)
        for f in files:
            print(f"{subindent}{f}")
else:
    print("Path does not exist")
