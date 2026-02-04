---
description: "How to deploy services as LXC containers"
---

# Deploy LXC Services (PoC)

This workflow describes how to move services from the host to isolated LXC containers using NixOS generators and Terranix.

## 1. Concept
1.  **Define**: The service is defined as a standard NixOS module in `nix-config/hosts/<service>/configuration.nix`.
2.  **Generate**: We use `nixos-generators` to build a metadata-enriched LXC tarball.
3.  **Import**: The image is imported into the local `incus` storage pool.
4.  **Deploy**: Terraform (Terranix) launches the container using the imported image.

## 2. Deploy Actions

### n8n (Workflow Automation)
```bash
just deploy-n8n
```

### Open WebUI (AI Chat)
```bash
just deploy-webui
```

## 3. Infrastructure Management
To verify the state of your containers or apply changes without rebuilding images:

```bash
just deploy-infra
```

## 4. Verification
Check if the containers are running:

```bash
incus list
```

Services should be accessible at their mapped ports (e.g. `http://localhost:5678` for n8n).
