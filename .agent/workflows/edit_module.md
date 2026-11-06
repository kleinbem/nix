---
description: "Checklist and impact analysis for editing an existing module"
---

# Edit an Existing Module

When modifying a module, especially renaming options, follow these steps to ensure you don't break consumers:

1. In `nix-config`, run `just dev::impact <module-path>` to print a list of all consuming hosts. Also grep `docs/OPTIONS.md` for the namespace and `docs/IMPORTS.md` for
   the file: a module without `my.*` options has importers but no option consumers. IMPORTS.md
   lists only a host's direct imports, so also search for the files that import yours.
2. Make your desired changes.
3. **CRITICAL:** If you renamed an option (e.g. `my.services.x.enable` -> `my.services.y.enable`), update every consumer file identified in Step 1.
4. Run `just dev::sync-agent` to regenerate the docs, then `just dev::check-hosts`.
5. Before committing, run `just dev::impact --git` to re-confirm that the blast radius covers everything you touched.
