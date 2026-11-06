---
description: Unified Infrastructure Verification Suite
---

// turbo-all

# NixOS Infrastructure Verification

This workflow performs a comprehensive health check of the infrastructure, including partitioning, network services, and backup/recovery integrity.

## 1. Disko Partitioning Verification
Verify that the declarative disk configuration is syntactically correct and can be applied without errors.
> [!NOTE]
> This performs a dry-run format in a VM.

1. just disko::format --dry-run

## 2. Caddy & Network Connectivity
Verify that the Caddy reverse proxy is correctly routing traffic to backends and that the dashboard is accessible.

2. just nixos::test-caddy

## 3. Backup & Recovery Integrity
Execute the automated recovery test which simulates a backup cycle and verifies data restoration from a mock repository.
> [!IMPORTANT]
> This ensures that your backup logic is robust against configuration drifts.

3. just nixos::test-recovery

## 4. System Fleet Status
Check the status of all remote nodes and their health metrics via the Atlas MCP server.

4. mcp_workspace-atlas_get_fleet_status
