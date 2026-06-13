# Coding Standards

- **Switchboard Pattern**: Default `enable = false`. Hosts must explicitly opt in (`my.desktop.enable = true`).
- **Attrset Merging**: NEVER repeat keys.
  - Good: `my = { a.b = true; c.d = false; };`
  - Bad: `my.a.b = true; my.c.d = false;`
- **Clean Code**: Remove unused vars and empty `let in` blocks.
- **Strings**: Use `"` for simple, `''` for multi-line.
- **Secrets**: Use `sops-nix` (`config.sops.secrets."name".path`).
