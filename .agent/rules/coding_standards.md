# Nix Configuration Standards

This repository follows a strict "Switchboard" architecture for reproducible NixOS systems.

## 1. The Switchboard Pattern (Architecture)
- **Default Disable**: All modules must default to `enable = false`.
- **Explicit Enable**: Hosts must explicitly enable features via `bundle.nix` or direct imports.
  - *Example*: `my.desktop.enable = true;`
- **Module Structure**:
  - `modules/nixos`: System-level modules (services, virtualization, desktop).
  - `modules/home-manager`: User-level modules (dotfiles, terminal tools).
  - `options.my.*`: Namespace for all custom module options.

## 2. Code Quality & Linting (Statix)
- **Attribute Merging**: **CRITICAL**. Do not repeat attribute keys.
  - **Bad**:
    ```nix
    my.desktop.enable = true;
    my.services.ai.enable = true;
    ```
  - **Good**:
    ```nix
    my = {
      desktop.enable = true;
      services.ai.enable = true;
    };
    ```
- **Strings**: Use double quotes `"` for simple strings, `''` for multi-line.
- **Unused Variables**: Remove them.
- **Let Blocks**: Do not leave empty `let in` blocks.

## 3. Workflow & Tooling
- **Justfile**: Use `just` for common operations.
  - `just rebuild`: Standard switch.
  - `just rebuild-smart`: Safe switch (checks for massive rebuilds).
- **Secrets**: Use `sops-nix`. NEVER commit secrets to git.
  - Access secrets via `config.sops.secrets."name".path`.
- **Formatting**: All files must be formatted with `nixfmt`.

## 4. Documentation
- **Comment Headers**: Use clear section headers in host configurations.
  ```nix
  # ==========================================
  # 1. SECTION NAME
  # ==========================================
  ```
- **Artifacts**: Maintain `task.md` and `walkthrough.md` for complex changes.
