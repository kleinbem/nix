---
description: Build the OpenWrt router image
---

# Build Router Image

1. **Build the Image**

    ```bash
    just router build bpi-r4
    ```

    *This delegates to `../openwrt-builder` (a flat sibling of `nix/`, not nested under `openwrt/`).*

2. **Verify Artifacts**
    Check `../openwrt-builder/bin/targets/mediatek/filogic/` for the new image.
