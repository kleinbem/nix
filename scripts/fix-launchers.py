import os
import re

APP_DIR = os.path.expanduser("~/.local/share/applications")
MOZILLA_DIR = os.path.expanduser("~/.mozilla/firefox")

BANKING_SITES = [
    "revolut", "n26", "banking", "alliedirishbanks", "bankofireland", 
    "finanzonline", "sparkasse", "bank", "ebanking"
]

AI_SITES = [
    "claude.ai", "gemini.google.com", "chatgpt.com", "openai.com", "perplexity.ai"
]

def determine_profile(url):
    url_lower = url.lower()
    for site in BANKING_SITES:
        if site in url_lower:
            return "vault"
    for site in AI_SITES:
        if site in url_lower:
            return "laboratory"
    return "standard"

def fix_file(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    new_lines = []
    modified = False
    
    for line in lines:
        if line.startswith("Exec="):
            exec_line = line[5:].strip()
            
            # Extract URL
            url_match = re.search(r'https?://[^\s"]+', exec_line)
            url = url_match.group(0) if url_match else ""
            
            # Determine profile
            target_profile = determine_profile(url)
            profile_path = os.path.join(MOZILLA_DIR, target_profile)
            
            # Determine binary
            binary = "firefox-beta" # Default
            if "firefox-devedition" in exec_line:
                binary = "firefox-devedition"
            elif "firefox-nightly" in exec_line:
                binary = "firefox-beta" # Fallback since nightly is gone
            
            # Handle taskbar tabs vs other types
            if "-taskbar-tab" in exec_line:
                # Extract the tab ID
                tab_id_match = re.search(r'-taskbar-tab\s+"?([a-f0-9-]+)"?', exec_line)
                tab_id = tab_id_match.group(1) if tab_id_match else ""
                
                # Construct new Exec line
                # Note: We keep the -container 0 and other flags if they were there
                new_exec = f'"{binary}" "-taskbar-tab" "{tab_id}" "-new-window" "{url}" "-profile" "{profile_path}" "-container" "0"'
            else:
                # Generic fallback if it's not a taskbar tab
                new_exec = f'"{binary}" -P {target_profile} "{url}"'
            
            line = f"Exec={new_exec}\n"
            modified = True
            
        elif line.startswith("Icon="):
            # If the icon path points to an old profile, update it
            for p in ["standard", "laboratory", "vault", "nightly"]:
                if f"/.mozilla/firefox/{p}/" in line:
                    target_profile = determine_profile("") # Default icon logic might be tricky
                    # Actually, if we change the profile, the icon might be missing from the new profile's taskbartabs/icons dir.
                    # But the icons are usually in the profile directory.
                    # Let's see if we can find the icon in the target profile.
                    pass
            
        new_lines.append(line)
    
    if modified:
        with open(filepath, 'w') as f:
            f.writelines(new_lines)
        return True
    return False

def main():
    print(f"🔧 Repairing Firefox launchers in {APP_DIR}...")
    for filename in os.listdir(APP_DIR):
        if filename.startswith("org.mozilla.firefox.webapp-") and filename.endswith(".desktop"):
            filepath = os.path.join(APP_DIR, filename)
            if fix_file(filepath):
                print(f"✅ Fixed {filename}")
        elif filename.startswith("FFPWA-") and filename.endswith(".desktop"):
            # firefoxpwa launchers are harder to fix without firefoxpwa tool
            # but we can at least flag them
            print(f"⚠️ Skipping {filename} (firefoxpwa-based, requires tool repair)")

if __name__ == "__main__":
    main()
