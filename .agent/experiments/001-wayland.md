# Experiment: Wayland vs X11

**Status**: [Proposed]

## Hypothesis

Switching to Wayland will reduce screen tearing and improve gesture support on the workstation.

## Config Changes

- `services.xserver.enable = false;`
- `programs.hyprland.enable = true;`

## Success Criteria

- [ ] No flickering in Chrome.
- [ ] Screen sharing works (via xdg-portal).
