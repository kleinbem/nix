# AI Assistant Rules

Operating manual for AI editors working in this meta-workspace. Optimized for "don't miss changes" over "be philosophical."

## Always do first

1. Read **`nix-config/docs/SYSTEM_REFERENCE.md`** — current nixpkgs revisions, host list, active services. Auto-generated.
2. Read **`nix-config/docs/OPTIONS.md`** — every `my.*` option, where it's declared, which hosts consume it. Use this for blast-radius lookups *before* editing a module. Auto-generated.
3. Read **`nix-config/docs/IMPORTS.md`** — per-host module/preset import map plus reverse index. Use when an edit touches a module without `my.*` options (helpers, bundles, scripts). Auto-generated.
3. Look for an **`AGENTS.md`** in the directory you're editing. They exist at: repo root, `nix-config/`, `nix-config/modules/nixos/`, `nix-config/hosts/`, `nix-presets/`. (Tools that read `CLAUDE.md` or `GEMINI.md` will resolve those names via symlinks to the same content.)
4. If either doc looks stale: `just maintenance::sync-agent`.

## Core mandates

- **Use `just` recipes** over raw shell. Run `just` (no args) for the interactive hub.
- **Format before committing**: `just maintenance::fmt`.
- **Validate before claiming done**: `just maintenance::check` (eval nixos-nvme) or `just maintenance::check-all` (full audit).
- **Check blast radius before committing**: `just maintenance::impact` (scans modified files; pass paths to target). Catches "edited a module, forgot the other host that consumes it."
- **Check conventions**: `just maintenance::lint-conventions` (Switchboard pattern audit).
- **Never edit nix-config flake inputs** without running `just maintenance::sync-agent` afterwards.
- **No secrets in git** — use `sops-nix`, access via `config.sops.secrets."name".path`.

## Code rules

- All options live under `my.*`. Declarations only in `nix-config/modules/` or `nix-presets/`. Hosts only *set* options.
- Group attrsets: write `my = { x.y = …; };` not `my.x.y = …;` (statix enforces).
- Default `enable = false`. Hosts must opt in.
- Remove dead code, empty `let in`, unused vars (statix enforces).

## Recipes

### Add a system module

1. Create `nix-config/modules/nixos/<name>.nix` using the template in that dir's `AGENTS.md`.
2. **Add the import** to `nix-config/modules/nixos/default.nix` — easy to forget; without this the module is invisible.
3. Opt in from a host: `my.<area>.<name>.enable = true;`.
4. `just maintenance::sync-agent` (refreshes `OPTIONS.md`).
5. `just maintenance::check`.

### Add a container preset

See `nix-presets/AGENTS.md`. Key gotcha: register in `nix-presets/flake.nix` under `nixosModules`, otherwise hosts can't `inputs.nix-presets.nixosModules.<name>` it.

### Add a host

See `nix-config/hosts/AGENTS.md`. Key gotchas: must be added to `inventory.nix`, `flake.nix` (nix-config), and have a `nix-hardware` module.

### Edit an existing module

1. `just maintenance::impact <module-path>` — prints consuming hosts. Or grep `nix-config/docs/OPTIONS.md` for the namespace.
2. Make the change.
3. If you renamed an option, update every consumer file.
4. `just maintenance::sync-agent` then `just maintenance::check-hosts`.
5. Before committing: `just maintenance::impact --git` to re-confirm the blast radius covers what you touched.

### Bump a sub-flake input

1. Edit inside the sub-repo (`nix-config/`, `nix-presets/`, etc.). Local edits are picked up via `OVERRIDES` in `.just/common.just` — no push needed during iteration.
2. When ready to lock: `just maintenance::update-local`.
3. `just maintenance::check-all`.

### Debug a build failure

1. `just maintenance::check` first — fastest signal (single host eval).
2. If it's a VSCode extension blowing up the build: see `feedback_vscode_extensions_blocking` memory — common recurrence.
3. For full audit: `just maintenance::check-all`.

## Ground-truth & references

| Need | Look here |
|---|---|
| Current nixpkgs rev, host list | `nix-config/docs/SYSTEM_REFERENCE.md` (auto-gen) |
| All `my.*` options + consumers | `nix-config/docs/OPTIONS.md` (auto-gen) |
| Per-host module imports + reverse index | `nix-config/docs/IMPORTS.md` (auto-gen) |
| NixOS + OpenWrt inventory | `nix-config/inventory.nix` |
| Per-area conventions | `<dir>/AGENTS.md` files (also exposed as `CLAUDE.md` / `GEMINI.md` symlinks) |
| Architecture decisions | `.agent/decisions/` ADRs |
| OpenWrt / router context | `../openwrt/docs/SYSTEM_REFERENCE.md` |

## When stuck

- **Lock held / stale**: `just maintenance::who` shows who holds the workspace lock.
- **Health**: `just maintenance::health-check`, `just ai::ai-check`.
- **Cross-repo state**: `just status` (dashboard across all sub-repos).
