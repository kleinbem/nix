import 'common.just'

set working-directory := ".."

# --- NixOS Operations ---

[group("System")]
switch mode="" *args="":
    @echo "🏗️ Switching System Configuration..."
    @if [ -n "{{mode}}" ]; then \
        nh os switch . --specialisation {{mode}} -- {{OVERRIDES}} {{args}}; \
    else \
        nh os switch . -- {{OVERRIDES}} {{args}}; \
    fi

[group("System")]
build *args="":
    @echo "🔨 Building System Configuration..."
    nh os build . -- {{OVERRIDES}} {{args}}

[group("Development")]
dry-run *args="":
    @echo "🧪 Dry Run: Testing configuration activation..."
    nh os test . --dry --map -- {{OVERRIDES}} {{args}}

[group("Development")]
test *args="":
    @echo "🚦 Testing System Configuration (Activation Only)..."
    nh os test . -- {{OVERRIDES}} {{args}}

[group("System")]
[confirm("👢 This will make the current configuration the DEFAULT at boot. Proceed?")]
switch-boot:
    @echo "👢 Building and setting as boot default..."
    nh os boot . -- {{OVERRIDES}}

[group("Debugging")]
switch-debug:
    @echo "🐛 Switching with trace output..."
    nh os switch . -- --show-trace --verbose {{OVERRIDES}}

[group("Debugging")]
switch-boot-debug:
    @echo "👢 Debugging bootloader generation..."
    nh os boot . -- --show-trace --verbose {{OVERRIDES}}

[group("Development")]
sys-plan:
    @echo "📋 Reviewing system derivation changes..."
    @nix build .#nixosConfigurations.nixos-nvme.config.system.build.toplevel --no-link --print-out-paths {{OVERRIDES}} > /tmp/new-system
    nvd diff /run/current-system $(cat /tmp/new-system)

[group("Development")]
build-pkg pkg_name:
    @echo "📦 Building package: {{pkg_name}}..."
    nix build .#{{pkg_name}} {{OVERRIDES}}

[group("Development")]
test-integration *args="":
    @echo "🧪 Running integration tests..."
    nix flake check . {{OVERRIDES}} {{args}}

[group("Development")]
test-vm *args="":
    @echo "🖥️ Building and launching test VM..."
    nix build .#nixosConfigurations.nixos-nvme.config.system.build.vm {{OVERRIDES}} {{args}}
    ./result/bin/run-nixos-nvme-vm

# --- Workload Profile Management (Specialisations) ---

[group("Modes")]
modes:
    @echo "🎭 Available System Modes:"
    @nix eval .#nixosConfigurations.nixos-nvme.config.specialisation --keys

[group("Modes")]
mode name:
    @just nixos::switch {{name}}

[group("Modes")]
reset-mode *args="":
    @nh os switch . -- {{OVERRIDES}} {{args}}

[group("Debugging")]
verify-caddy:
    @echo "🔍 Verifying Caddy Gateway..."
    @for i in {1..5}; do curl -k -s https://10.85.46.107 > /dev/null && echo "✅ Caddy is responsive" && exit 0 || echo "⏳ Waiting for Caddy... ($i/5)" && sleep 2; done
    @echo "❌ Caddy is NOT responsive. Checking status..."
    @systemctl status container@caddy.service --no-pager || true
    @echo "📜 Recent Logs:"
    @journalctl -u container@caddy.service -n 20 --no-pager

[group("Development")]
topology:
    @echo "🗺️ Rendering Infrastructure Topology..."
    @nix build .#topology.x86_64-linux.config.build.svg --no-link --print-out-paths > /tmp/topo-path
    @echo "✅ Rendered to: $(cat /tmp/topo-path)/main.svg"
    @if [ -n "$DISPLAY" ]; then xdg-open "$(cat /tmp/topo-path)/main.svg"; else echo "🔗 File path: $(cat /tmp/topo-path)/main.svg"; fi
