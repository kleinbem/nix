#!/usr/bin/env python3
"""Blast-radius lookup for changed files.

Usage:
  scripts/impact.py path/to/file.nix [more files…]
  scripts/impact.py --git              # use git's modified/untracked files

For each path, prints which hosts / users / presets are downstream consumers.

Designed to be run before committing — catches the common AI failure mode of
editing a module without realizing two other hosts also consume it.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _nix_options import (  # noqa: E402
    CONSUMER_DIRS,
    MODULE_DIRS,
    REPO,
    consumer_label,
    consumer_paths_in_file,
    declarations_in_file,
    iter_nix_files,
    relpath,
)


def git_changed_files() -> list[Path]:
    """All files that git status reports as modified, added, or untracked
    across every nested git repo this script can see from REPO. Submodules
    are searched independently because their porcelain output is relative to
    the submodule root."""
    paths: list[Path] = []
    # Outer repo
    repos = [REPO]
    # Detect submodules via .gitmodules
    gitmodules = REPO / ".gitmodules"
    if gitmodules.exists():
        for line in gitmodules.read_text().splitlines():
            line = line.strip()
            if line.startswith("path ="):
                sub = REPO / line.split("=", 1)[1].strip()
                if sub.exists():
                    repos.append(sub)
    for r in repos:
        try:
            out = subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=r, text=True
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
        for line in out.splitlines():
            if len(line) < 4:
                continue
            # Format: "XY path" or "XY path -> path"
            rest = line[3:]
            if "->" in rest:
                rest = rest.split("->", 1)[1].strip()
            p = (r / rest.strip()).resolve()
            if p.suffix == ".nix" and p.exists():
                paths.append(p)
    return paths


def classify(path: Path) -> str:
    """Return a short tag describing what kind of file this is."""
    try:
        rel = path.resolve().relative_to(REPO)
    except ValueError:
        return "external"
    parts = rel.parts
    if parts[:2] == ("nix-config", "hosts"):
        return "host"
    if parts[:2] == ("nix-config", "users"):
        return "user"
    if parts[:2] == ("nix-config", "modules"):
        return "module"
    if parts[0] == "nix-presets":
        return "preset"
    if parts[0] == "nix-hardware":
        return "hardware"
    if parts[0] == "nix-packages":
        return "package"
    if parts[0] == "nix-devshells":
        return "devshell"
    if parts[0] == "nix-secrets":
        return "secrets"
    if parts[0] == "nix-templates":
        return "template"
    return "other"


def host_consumers_of_namespaces(namespaces: set[str]) -> dict[str, set[str]]:
    """For a set of `my.X` namespaces, return {namespace: {consumer labels}}."""
    out: dict[str, set[str]] = {ns: set() for ns in namespaces}
    for d in CONSUMER_DIRS:
        for f in iter_nix_files(d):
            paths = consumer_paths_in_file(f)
            if not paths:
                continue
            for ns in namespaces:
                for p in paths:
                    if p == ns or p.startswith(ns + "."):
                        out[ns].add(consumer_label(f))
                        break
    return out


def hosts_importing_user(user_name: str) -> list[str]:
    """Find hosts that import this user's nixos module."""
    hosts_dir = REPO / "nix-config/hosts"
    needle = f"users/{user_name}/"
    hits = []
    for f in iter_nix_files(hosts_dir):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if needle in text:
            hits.append(f.parent.name)
    return sorted(set(hits))


def hosts_importing_preset(preset_label: str) -> list[str]:
    """Heuristic: hosts that grep-match `nixosModules.<basename>`.

    `preset_label` is e.g. `preset:nix-presets/containers/attic.nix` —
    the module name is typically the filename stem.
    """
    # Extract filename stem
    rel = preset_label.split(":", 1)[1]
    stem = Path(rel).stem
    if stem == "default":
        stem = Path(rel).parent.name
    hosts_dir = REPO / "nix-config/hosts"
    needle = f"nixosModules.{stem}"
    hits = []
    for f in iter_nix_files(hosts_dir):
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if needle in text:
            hits.append(f.parent.name)
    return sorted(set(hits))


def report_for_path(path: Path) -> list[str]:
    """Return human-readable lines describing the blast radius."""
    lines: list[str] = []
    kind = classify(path)
    rel = relpath(path)
    lines.append(f"📄 {rel}  ({kind})")

    if kind in ("module", "preset"):
        decls = declarations_in_file(path)
        if decls:
            namespaces = {d.namespace for d in decls}
            consumers = host_consumers_of_namespaces(namespaces)
            for ns in sorted(namespaces):
                cs = sorted(consumers.get(ns, set()))
                if cs:
                    lines.append(f"   ↳ `{ns}` → {', '.join(cs)}")
                else:
                    lines.append(f"   ↳ `{ns}` → (no opt-ins detected)")
        # Even files without `options.my.*` can be imported as nixosModules
        if kind == "preset":
            hosts = hosts_importing_preset(f"preset:{rel}")
            if hosts:
                lines.append(f"   ↳ imported as preset by hosts: {', '.join(hosts)}")
    elif kind == "host":
        # Host edits affect only that host
        parts = path.resolve().relative_to(REPO).parts
        if len(parts) >= 3:
            lines.append(f"   ↳ affects host: {parts[2]}")
    elif kind == "user":
        parts = path.resolve().relative_to(REPO).parts
        if len(parts) >= 3:
            user = parts[2]
            hosts = hosts_importing_user(user)
            if hosts:
                lines.append(f"   ↳ user `{user}` imported by hosts: {', '.join(hosts)}")
            else:
                lines.append(f"   ↳ user `{user}` not currently imported by any host")
    elif kind == "hardware":
        lines.append("   ↳ check which host imports this hardware module via nix-hardware")
    elif kind == "secrets":
        lines.append("   ↳ secrets change — every host using sops will see it on next switch")
    else:
        lines.append(f"   ↳ no automatic impact analysis for `{kind}` — review manually")
    return lines


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0

    paths: list[Path]
    if argv[0] == "--git":
        paths = git_changed_files()
        if not paths:
            print("No changed .nix files in any tracked git repo.")
            return 0
    else:
        paths = []
        for a in argv:
            p = Path(a).resolve()
            if not p.exists():
                print(f"⚠️  {a}: file not found", file=sys.stderr)
                continue
            paths.append(p)

    if not paths:
        return 1

    for i, p in enumerate(paths):
        if i:
            print()
        for line in report_for_path(p):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
