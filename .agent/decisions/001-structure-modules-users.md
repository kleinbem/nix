# 001-structure-modules-users.md

## Title

Separation of `modules` and `users` directories

## Status

Accepted

## Context

Initial setup used a `home/` directory for user configurations. However, this creates ambiguity with `modules/home-manager/` (logic) vs actual user configs (data). Standard NixOS patterns often mix these or hide them in `hosts/`.

## Decision

We renamed `home/` to `users/`.

- `modules/*`: Contains reusable code (logic, options).
- `users/*`: Contains actual person-specific configurations (inputs).
- `hosts/*`: Contains machine-specific configurations.

## Consequences

- **Easier**: Clear distinction between writing a tool (`modules`) and using a tool (`users`).
- **Harder**: Requires updating import paths when moving existing configs.
