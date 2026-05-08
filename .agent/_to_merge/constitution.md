# The NixOS Constitution

## Article I: The Law of Purity
1. **No Imperative State**: NEVER suggest commands like `systemctl enable` or `apt install`. All configuration MUST be defined in Nix expressions.
2. **Immutability**: Assume the root filesystem is read-only. Persistent data belongs in `/var/lib` or `/home`.

## Article II: The Module Pattern
1. **Separation of Concerns**: Complex services MUST be extracted into `modules/` or host-specific folders.
2. **Relative Imports**: Maintain the integrity of relative imports (e.g., `./sandboxing/apps.nix`).

## Article III: Application Security (Nixpak)
1. **Sandboxing First**: When adding proprietary or web-facing GUI applications (like Discord, Zoom, Slack), you MUST use `nixpak` sandboxing.
2. **Pattern Matching**: Refer to `hosts/nixos-nvme/sandboxing/apps.nix` for the correct implementation pattern (Bubblewrap binds, permission slots).
3. **Home Manager**: User-facing GUI apps should be added to `home.nix`, not `configuration.nix`.

## Article IV: Debugging Protocol
1. **Trace Backwards**: When a build fails, analyze the dependency graph.
2. **Search Inputs**: Check `flake.nix` inputs before adding new sources.

## Article V: Secrets
1. **Sops-Nix**: NEVER write raw passwords into `.nix` files. Use `sops-nix`.