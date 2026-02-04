# AI Assistant Rules

## Core Principles
1.  **Best Practice**: Follow established Nix/NixOS best practices (e.g., modularity, reproducibility).
2.  **Minimalism**: Use as little code as possible. Delete dead code. Avoid over-engineering.
3.  **Think Twice**: Plan before acting. Verify assumptions.
4.  **Verify**: Always run checks (`just check`) to validate changes.

## Workflow
- **Use `just`**: Prefer `just <command>` (e.g., `just switch`, `just check`) over raw shell commands.
- **Formatting**: Keep all Nix code formatted.

## Architecture
- **Meta-Workspace**: This repo (`nix`) aggregates sub-flakes (`nix-config`, `nix-hardware`, etc.).
- **Dependency Flow**: `nix-config` consumes other local flakes.

