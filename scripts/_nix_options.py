"""Shared parser for `my.*` option declarations and opt-ins.

Used by:
  - generate-options-index.py (builds nix-config/docs/OPTIONS.md)
  - impact.py                  (blast-radius lookup for a changed file)
  - lint-conventions.py        (enforces my.* namespace + declaration locations)

Static analysis only — never invokes `nix eval`. The cost of false positives
from regex parsing is acceptable for these tools; the cost of evaluation
failures blocking them is not.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

MODULE_DIRS = [
    REPO / "nix-config/modules/nixos",
    REPO / "nix-config/modules/home-manager",
    REPO / "nix-presets",
]

CONSUMER_DIRS = [
    REPO / "nix-config/hosts",
    REPO / "nix-config/users",
    REPO / "nix-presets",
]

# `options.my.<path> = {` — namespace declaration on a my.* path
OPT_DECL_RE = re.compile(r"^[ \t]*options\.(my(?:\.[a-zA-Z0-9_-]+)+)\s*=\s*\{", re.MULTILINE)

# Any `options.<path> = {` declaration block (used by the lint to flag non-my.*)
ANY_OPT_DECL_RE = re.compile(
    r"^[ \t]*options\.([a-zA-Z_][a-zA-Z0-9_.-]*)\s*=\s*\{", re.MULTILINE
)

# Explicit assignment: `my.X.Y[.Z…] = …`
MY_DOT_RE = re.compile(r"\bmy((?:\.[a-zA-Z0-9_-]+)+)\s*=")

# Start of a `my = { … }` group
MY_BLOCK_RE = re.compile(r"\bmy\s*=\s*\{")

# Any `options.<path>` declaration — used for stripping before consumer scan
OPT_DECL_BLOCK_RE = re.compile(r"\boptions\.[a-zA-Z_][a-zA-Z0-9_.-]*\s*=\s*\{")

# Top-level `key.path = …` inside an attrset
ATTR_LINE_RE = re.compile(r"([a-zA-Z_][a-zA-Z0-9_-]*(?:\.[a-zA-Z_][a-zA-Z0-9_-]*)*)\s*=")


@dataclass
class Declaration:
    namespace: str
    file: Path
    line: int
    sub_options: list[str] = field(default_factory=list)


def strip_comments_and_strings(src: str) -> str:
    """Replace line comments, block comments, and string literals with spaces.
    Preserves offsets and line numbers so positions stay meaningful.
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "#":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            out.append("  ")
            i += 2
            while i < n - 1 and not (src[i] == "*" and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append("  ")
                i += 2
            continue
        if c == "'" and i + 1 < n and src[i + 1] == "'":
            out.append("  ")
            i += 2
            while i < n - 1 and not (src[i] == "'" and src[i + 1] == "'"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append("  ")
                i += 2
            continue
        if c == '"':
            out.append(" ")
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            if i < n:
                out.append(" ")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def find_matching_brace(src: str, open_pos: int) -> int:
    """Position is just past an opening `{`. Returns position of the matching
    `}` (the character itself), or -1 on mismatch. Input should be stripped.
    """
    depth = 1
    i = open_pos
    n = len(src)
    while i < n:
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def blank_declaration_blocks(src: str) -> str:
    """Whitespace out every `options.<…> = { … }` so the consumer scanner
    doesn't mistake a module's own declarations for self-consumption.
    """
    out = list(src)
    for m in OPT_DECL_BLOCK_RE.finditer(src):
        open_brace = src.find("{", m.start())
        if open_brace < 0:
            continue
        close = find_matching_brace(src, open_brace + 1)
        if close < 0:
            continue
        for i in range(m.start(), close + 1):
            if out[i] != "\n":
                out[i] = " "
    return "".join(out)


def extract_paths_from_block(block: str, prefix: str) -> set[str]:
    """Walk attrset body, return dotted paths under `prefix`.
    Recurses into nested attrsets. Block must already be stripped.
    """
    paths: set[str] = set()
    i, n = 0, len(block)
    while i < n:
        c = block[i]
        if c.isspace() or c in ";,":
            i += 1
            continue
        m = ATTR_LINE_RE.match(block, i)
        if not m:
            i += 1
            continue
        key = m.group(1)
        rhs_start = m.end()
        while rhs_start < n and block[rhs_start].isspace():
            rhs_start += 1
        full_path = f"{prefix}.{key}"
        if rhs_start < n and block[rhs_start] == "{":
            close = find_matching_brace(block, rhs_start + 1)
            if close < 0:
                break
            inner = block[rhs_start + 1 : close]
            paths.add(full_path)
            paths |= extract_paths_from_block(inner, full_path)
            i = close + 1
        else:
            paths.add(full_path)
            depth = 0
            j = rhs_start
            while j < n:
                ch = block[j]
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    if depth == 0:
                        break
                    depth -= 1
                elif ch == ";" and depth == 0:
                    j += 1
                    break
                j += 1
            i = j
    return paths


def consumer_paths_in_file(path: Path) -> set[str]:
    """Return every `my.X.Y…` path this file appears to set."""
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    src = strip_comments_and_strings(raw)
    src = blank_declaration_blocks(src)
    paths: set[str] = set()
    for m in MY_DOT_RE.finditer(src):
        paths.add("my" + m.group(1))
    for m in MY_BLOCK_RE.finditer(src):
        close = find_matching_brace(src, m.end())
        if close < 0:
            continue
        inner = src[m.end() : close]
        paths |= extract_paths_from_block(inner, "my")
    return paths


def declarations_in_file(path: Path) -> list[Declaration]:
    """Find every `options.my.X = { … }` declaration in this file."""
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    src = strip_comments_and_strings(raw)
    decls: list[Declaration] = []
    for m in OPT_DECL_RE.finditer(src):
        namespace = m.group(1)
        line = src.count("\n", 0, m.start()) + 1
        open_paren = src.find("{", m.start())
        if open_paren < 0:
            continue
        close = find_matching_brace(src, open_paren + 1)
        if close < 0:
            continue
        body = src[open_paren + 1 : close]
        all_sub = {s.lstrip(".") for s in extract_paths_from_block(body, "") if s}
        leaves = sorted(
            s for s in all_sub
            if not any(other != s and other.startswith(s + ".") for other in all_sub)
        )
        decls.append(Declaration(namespace=namespace, file=path, line=line, sub_options=leaves))
    return decls


def any_options_decls_in_file(path: Path) -> list[tuple[str, int]]:
    """Every `options.<path>` declaration site (returns the dotted path and line).
    Includes non-my.* declarations — used by the convention lint.
    """
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    src = strip_comments_and_strings(raw)
    out = []
    for m in ANY_OPT_DECL_RE.finditer(src):
        line = src.count("\n", 0, m.start()) + 1
        out.append((m.group(1), line))
    return out


def iter_nix_files(root: Path):
    if not root.exists():
        return
    for p in root.rglob("*.nix"):
        parts = set(p.parts)
        if parts & {".direnv", ".devenv", "result", ".git"}:
            continue
        yield p


def consumer_label(path: Path) -> str:
    """Human label for a consumer file."""
    rel = path.relative_to(REPO)
    parts = rel.parts
    if parts[:2] == ("nix-config", "hosts") and len(parts) >= 3:
        return f"host:{parts[2]}"
    if parts[:2] == ("nix-config", "users") and len(parts) >= 3:
        return f"user:{parts[2]}"
    if parts[0] == "nix-presets":
        return f"preset:{rel.as_posix()}"
    return rel.as_posix()


def relpath(p: Path) -> str:
    return p.relative_to(REPO).as_posix()
