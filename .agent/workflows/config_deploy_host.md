---
description: "Deploy and verify configuration on a remote host"
---

# Deploy Remote Host
// turbo-all

Follow this procedure to bring a remote host (like Orin Nano or RPi) online with its latest configuration.

## 1. Verify Connectivity
Check if the host is reachable via the mesh network before attempting deployment.
```bash
# Use MCP to check fleet status
# mcp_workspace-atlas_get_fleet_status
```

## 2. Check Prerequisites
Ensure you are in the correct devshell and have necessary secrets.
```bash
# mcp_workspace-atlas_check_ai_stack_health --target_host <HOST_NAME>
```

## 3. Apply Configuration
Deploy the configuration using Colmena or `just`.
```bash
# Replace <HOST_NAME> with the actual host (e.g., orin-nano)
just deployment::remote <HOST_NAME>
```

## 4. Post-Deployment Health Check
Verify all services are running correctly on the target host.
```bash
# mcp_workspace-atlas_check_ai_stack_health --target_host <HOST_NAME>
```

## 5. Update Task List
Mark the host as online in our tracking system.
```bash
# mcp_workspace-atlas_update_todo --task "Bring <HOST_NAME> online" --status "done"
```
