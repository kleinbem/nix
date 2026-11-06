import 'common.just'

set working-directory := ".."

# Separate from nixos-rebuild so a broken extension never blocks a switch. The
# editors link straight into the store, so each bundle keeps a GC root under
# ~/.local/state/editor-extensions or garbage collection breaks every link.
# Build and sync editor extensions from the nix-presets flake.
[group("Desktop")]
sync:
    @echo "🧩 Syncing editor extensions..."
    @mkdir -p "$HOME/.local/state/editor-extensions"
    @for editor in cursor windsurf antigravity; do \
        echo "  ⚙ Building $editor extensions..."; \
        if bundle=$(nix build --print-out-paths \
            --out-link "$HOME/.local/state/editor-extensions/$editor" \
            "git+file://{{ROOT}}/nix-presets#$editor-extensions-bundle" 2>/dev/null); then \
            if [ "$editor" = "antigravity" ]; then \
                ext_dir="$HOME/.antigravity-ide/extensions"; \
            else \
                ext_dir="$HOME/.config/$editor/extensions"; \
            fi; \
            mkdir -p "$ext_dir"; \
            find "$ext_dir" -maxdepth 1 -type l | while IFS= read -r link; do \
                target=$(readlink "$link"); \
                case "$target" in /nix/store/*) rm -f "$link";; esac; \
            done; \
            for ext in "$bundle"/share/vscode/extensions/*; do \
                ln -sf "$ext" "$ext_dir/$(basename "$ext")"; \
            done; \
            echo "  ✅ $editor synced"; \
        else \
            echo "  ⚠ $editor build failed — skipping (run 'just extensions::sync' later)"; \
        fi; \
    done
