---
description: Build the OpenWrt router image
---

# Build Router Image

1. **Build the Image**

    ```bash
    just router build bpi-r4
    ```

    *This delegates to `openwrt/openwrt-builder`.*

2. **Verify Artifacts**
    Check `openwrt/openwrt-builder/bin/targets/mediatek/filogic/` for the new image.
