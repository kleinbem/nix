---
description: Update and switch the NixOS system configuration
---

# Update System

1. **Run the update**

    ```bash
    just nix switch
    ```

    *This delegates to `nix/nix-config` and runs `nh os switch`.*

// turbo
2.  **Verify Services**
    ```bash
    systemctl list-units --failed
    ```
