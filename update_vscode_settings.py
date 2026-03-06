import json
import os

settings_path = os.path.expanduser('~/.config/Code/User/settings.json')
with open(settings_path, 'r') as f:
    settings = json.load(f)

# Ensure nix language server is enabled
settings.setdefault('[nix]', {})
settings['[nix]']['editor.defaultFormatter'] = 'jnoortheen.nix-ide'

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
