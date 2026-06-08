#!/usr/bin/env python3
"""Generate nix-config/docs/OPTIONS.md — a machine-readable index of every
`my.*` option, its declaration site, sub-options, and consuming hosts.

Used by AI editors as a single-document blast-radius lookup before changing
a module. Regenerated via `just maintenance::sync-agent`.

Static analysis only. See _nix_options.py for the shared parser.
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _nix_options import (  # noqa: E402
    CONSUMER_DIRS,
    MODULE_DIRS,
    REPO,
    Declaration,
    consumer_label,
    consumer_paths_in_file,
    declarations_in_file,
    iter_nix_files,
    relpath,
)

OUTPUT = REPO / "nix-config/docs/OPTIONS.md"


def main() -> int:
    decls: list[Declaration] = []
    for d in MODULE_DIRS:
        for f in iter_nix_files(d):
            decls.extend(declarations_in_file(f))

    if not decls:
        print("No my.* option declarations found — refusing to overwrite OPTIONS.md", file=sys.stderr)
        return 1

    file_to_paths: dict[Path, set[str]] = {}
    for d in CONSUMER_DIRS:
        for f in iter_nix_files(d):
            paths = consumer_paths_in_file(f)
            if paths:
                file_to_paths[f] = paths

    namespace_consumers: dict[str, set[Path]] = defaultdict(set)
    for f, paths in file_to_paths.items():
        for decl in decls:
            ns = decl.namespace
            for p in paths:
                if p == ns or p.startswith(ns + "."):
                    namespace_consumers[ns].add(f)
                    break

    by_top: dict[str, list[Declaration]] = defaultdict(list)
    for d in decls:
        top = d.namespace.split(".")[1] if "." in d.namespace else d.namespace
        by_top[f"my.{top}"].append(d)

    lines: list[str] = []
    lines.append("# `my.*` Options Index")
    lines.append("")
    lines.append("> **Auto-generated** by `scripts/generate-options-index.py`. Do not edit by hand.")
    lines.append(">")
    lines.append("> Regenerate with `just maintenance::sync-agent`.")
    lines.append("")
    lines.append(
        "Use this index to find (1) where an option is declared and (2) which "
        "hosts / users / presets opt into it. Before editing a module, grep "
        "this file for the namespace to see the blast radius."
    )
    lines.append("")
    lines.append(f"**Declarations indexed:** {len(decls)}  ")
    lines.append(f"**Consumer files scanned:** {len(file_to_paths)}")
    lines.append("")
    lines.append("---")
    lines.append("")

    for top in sorted(by_top):
        lines.append(f"## `{top}`")
        lines.append("")
        for decl in sorted(by_top[top], key=lambda d: d.namespace):
            lines.append(f"### `{decl.namespace}`")
            lines.append("")
            lines.append(f"- **Declared:** `{relpath(decl.file)}:{decl.line}`")
            if decl.sub_options:
                opts = ", ".join(f"`{s}`" for s in decl.sub_options)
                lines.append(f"- **Sub-options:** {opts}")
            consumers = sorted({consumer_label(f) for f in namespace_consumers.get(decl.namespace, set())})
            if consumers:
                lines.append(f"- **Consumed by:** {', '.join(f'`{c}`' for c in consumers)}")
            else:
                lines.append("- **Consumed by:** _(no opt-ins detected)_")
            lines.append("")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"✅ Wrote {relpath(OUTPUT)} ({len(decls)} namespaces, {len(file_to_paths)} consumer files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
