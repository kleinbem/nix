# AI Rules

Read before acting:
1. `nix-config/docs/SYSTEM_REFERENCE.md`: Current nixpkgs rev, host list.
2. `nix-config/docs/OPTIONS.md`: All `my.*` options & consumers.
3. `nix-config/docs/IMPORTS.md`: Per-host import map.
If stale, run `just maintenance::sync-agent`.

Commands:
- Run `just` for interactive hub.
- `just maintenance::fmt` (format before committing).
- `just maintenance::check` (eval test).
- `just maintenance::impact <path>` (check blast radius).

Mandates:
- All options are `my.*`. Default `enable = false`.
- Never repeat attrsets: `my = { x.y = true; };` NOT `my.x.y = true;`.
- No secrets in git (use `sops-nix`).
- Explicit imports only, no magic auto-loaders.
