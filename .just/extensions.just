import 'common.just'

set working-directory := ".."

# Build and sync editor extensions from the nix-presets flake.
# Runs independently of nixos-rebuild — a broken extension never blocks a system switch.
[group("Desktop")]
sync:
    @echo "🧩 Syncing editor extensions..."
    @for editor in antigravity cursor windsurf; do \
        echo "  ⚙ Building $editor extensions..."; \
        if bundle=$(nix build --no-link --print-out-paths \
            "git+file://{{ROOT}}/nix-presets#$editor-extensions-bundle" 2>/dev/null); then \
            ext_dir="$HOME/.config/$editor/extensions"; \
            mkdir -p "$ext_dir"; \
            find "$ext_dir" -maxdepth 1 -type l | while read link; do \
                target=$(readlink "$link"); \
                case "$target" in /nix/store/*) rm -f "$link";; esac; \
            done; \
            for ext in $bundle/share/vscode/extensions/*; do \
                ln -sf "$ext" "$ext_dir/$(basename $ext)"; \
            done; \
            echo "  ✅ $editor synced"; \
        else \
            echo "  ⚠ $editor build failed — skipping (run 'just extensions::sync' later)"; \
        fi; \
    done
