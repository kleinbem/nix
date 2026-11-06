---
description: "Troubleshooting steps for build and evaluation failures"
---

# Debug a Build Failure

When a Nix build or evaluation fails:

1. **Fastest Signal:** Run `just maintenance::check` first. This does a single host evaluation and provides the quickest feedback loop.
2. **VSCode Extensions:** If it's a VSCode extension blowing up the build (a very common recurrence), check the `feedback_vscode_extensions_blocking` memory or knowledge items.
3. **Full Audit:** Run `just maintenance::check-all` for a comprehensive audit across all sub-flakes.
4. Review recent edits using `just status` to see what changed across the sub-repos.
