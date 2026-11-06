# Workflow: Deploy NixOS LXC to OpenWrt

This workflow describes how to build and deploy NixOS LXC containers (like `router-1`) to an OpenWrt host.

## Prerequisites
- The target router (e.g., `router-b` @ 192.168.1.2) must have `lxc` installed and a storage directory at `/srv/lxc`.
- SSH access to the router as `root`.

## Deployment Steps

1. **Build the LXC Image**
   - Run the build command for the specific host:
     ```bash
     nix build ".#nixosConfigurations.router-1.config.system.build.tarball" --out-link result-router-1
     ```

2. **Upload to Router**
   - Push the tarball to the router's staging area:
     ```bash
     scp result-router-1/tarball/*.tar.xz root@192.168.1.2:/srv/lxc/nixos-router-1.tar.xz
     ```

3. **Activate on Router**
   - SSH into the router and refresh the container:
     ```bash
     ssh root@192.168.1.2 "
       lxc-stop -n router-1 || true
       mkdir -p /srv/lxc/router-1/rootfs
       tar -xf /srv/lxc/nixos-router-1.tar.xz -C /srv/lxc/router-1/rootfs
       lxc-start -n router-1
     "
```

## Automating with Just
Use the orchestrated command:
```bash
just deploy-router-lxc router-1
```
