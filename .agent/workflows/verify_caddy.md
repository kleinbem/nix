---
description: Verify Caddy service and dashboard accessibility
---

1. Apply the local configuration change
// turbo
2. just switch-local

3. Wait for Caddy to become responsive (retry loop)
// turbo
4. for i in {1..10}; do curl -k -v https://10.85.46.107 && break || sleep 5; done

5. Check Caddy service status on the host (if failed)
// turbo
6. systemctl status container@caddy.service --no-pager

7. Check Caddy internal logs (via journalctl on host)
// turbo
8. journalctl -u container@caddy.service -n 50 --no-pager
