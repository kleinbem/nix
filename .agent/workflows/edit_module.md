---
description: "Checklist and impact analysis for editing an existing module"
---

# Edit an Existing Module

When modifying a module, especially renaming options, follow these steps to ensure you don't break consumers:

1. Run `just maintenance::impact <module-path>` to print a list of all consuming hosts. Alternatively, grep `nix-config/docs/OPTIONS.md` for the namespace.
2. Make your desired changes.
3. **CRITICAL:** If you renamed an option (e.g. `my.services.x.enable` -> `my.services.y.enable`), update every consumer file identified in Step 1.
4. Run `just maintenance::sync-agent` to regenerate the docs, then run `just maintenance::check-hosts`.
5. Before committing, run `just maintenance::impact --git` to re-confirm that the blast radius covers everything you touched.
