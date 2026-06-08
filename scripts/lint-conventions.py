#!/usr/bin/env python3
"""Check Switchboard-pattern conventions across the workspace.

Hard rules (cause non-zero exit):
  • Host files (`nix-config/hosts/**.nix`) must not declare any `options.*`.
    Hosts only *set* options.
  • User files (`nix-config/users/**.nix`) must not declare any `options.*`.

Soft warnings (informational, do not fail):
  • Module / preset declarations outside known namespaces. Two namespaces are
    treated as first-party: `my.*` (NixOS modules) and `modules.*` (home-manager).
    Extending upstream namespaces (`services.*`, `programs.*`, `systemd.*`, …)
    is allowed; anything else is flagged for review.

This lint deliberately under-enforces. The point is to surface drift without
blocking legitimate patterns. Use `--strict` to promote warnings to errors.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _nix_options import (  # noqa: E402
    REPO,
    any_options_decls_in_file,
    iter_nix_files,
    relpath,
)

HOST_DIR = REPO / "nix-config/hosts"
USER_DIR = REPO / "nix-config/users"

MODULE_DIRS = [
    REPO / "nix-config/modules/nixos",
    REPO / "nix-config/modules/home-manager",
    REPO / "nix-presets",
]

# First-party option namespaces (top-level segment of `options.X.…`)
FIRST_PARTY = {"my", "modules"}

# Upstream nixpkgs / module-system namespaces. Modules may extend these.
UPSTREAM = {
    "services", "programs", "systemd", "security", "boot", "networking",
    "nix", "hardware", "environment", "virtualisation", "sops", "fileSystems",
    "swapDevices", "system", "users", "fonts", "time", "i18n", "console",
    "location", "sound", "xdg", "home", "wayland", "qt",
}


def main(argv: list[str]) -> int:
    strict = "--strict" in argv
    errors: list[str] = []
    warnings: list[str] = []

    # Hard rule: no `options.*` in hosts/ or users/
    for label, root in (("host", HOST_DIR), ("user", USER_DIR)):
        for f in iter_nix_files(root):
            for path, line in any_options_decls_in_file(f):
                errors.append(
                    f"{relpath(f)}:{line}: {label} file declares `options.{path}` "
                    f"— move the declaration into a module under nix-config/modules/ or nix-presets/"
                )

    # Soft warning: declarations in module/preset files outside known namespaces
    for root in MODULE_DIRS:
        for f in iter_nix_files(root):
            for path, line in any_options_decls_in_file(f):
                top = path.split(".", 1)[0]
                if top in FIRST_PARTY or top in UPSTREAM:
                    continue
                warnings.append(
                    f"{relpath(f)}:{line}: declares `options.{path}` outside "
                    f"`my.*`, `modules.*`, or a known upstream namespace"
                )

    if warnings:
        print(f"⚠️  {len(warnings)} warning(s):")
        for w in warnings:
            print(f"   {w}")
        print()

    if errors:
        print(f"❌ {len(errors)} error(s):")
        for e in errors:
            print(f"   {e}")
        return 2

    if strict and warnings:
        return 1

    if not warnings:
        print("✅ All Switchboard conventions satisfied.")
    else:
        print(f"✅ No hard errors. {len(warnings)} warning(s) to review (use --strict to fail on warnings).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
