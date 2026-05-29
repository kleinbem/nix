import 'common.just'

set working-directory := ".."

# --- NixOS Operations ---

[group("System")]
switch auth="" mode="" *args="":
    #!/usr/bin/env bash
    ACTUAL_MODE="{{mode}}"
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    else
        if [ -n "{{auth}}" ]; then
            ACTUAL_MODE="{{auth}}"
        fi
    fi
    echo "🏗️ Switching System Configuration..."
    if [ -n "$ACTUAL_MODE" ]; then
        {{LOCK_CMD}} {{TIMER}} nh os switch . --specialisation "$ACTUAL_MODE" -- {{OVERRIDES}} {{args}}
    else
        {{LOCK_CMD}} {{TIMER}} nh os switch . -- {{OVERRIDES}} {{args}}
    fi

[group("System")]
build *args="":
    @echo "🔨 Building System Configuration..."
    @{{LOCK_CMD}} {{TIMER}} nh os build . -- {{OVERRIDES}} {{args}}

[group("Development")]
dry-run *args="":
    @echo "🧪 Dry Run: Testing configuration activation..."
    @{{LOCK_CMD}} {{TIMER}} nh os test . --dry -- {{OVERRIDES}} {{args}}

[group("Development")]
test *args="":
    @echo "🚦 Testing System Configuration (Activation Only)..."
    @{{LOCK_CMD}} {{TIMER}} nh os test . -- {{OVERRIDES}} {{args}}

[group("System")]
[confirm("👢 This will make the current configuration the DEFAULT at boot. Proceed?")]
switch-boot auth="":
    #!/usr/bin/env bash
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    echo "👢 Building and setting as boot default..."
    {{LOCK_CMD}} nh os boot . -- {{OVERRIDES}}

[group("Debugging")]
switch-debug auth="" mode="" *args="":
    #!/usr/bin/env bash
    ACTUAL_MODE="{{mode}}"
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    else
        if [ -n "{{auth}}" ]; then
            ACTUAL_MODE="{{auth}}"
        fi
    fi
    echo "🐛 Switching with trace output..."
    if [ -n "$ACTUAL_MODE" ]; then
        {{LOCK_CMD}} nh os switch . --specialisation "$ACTUAL_MODE" -- --show-trace --verbose {{OVERRIDES}} {{args}}
    else
        {{LOCK_CMD}} nh os switch . -- --show-trace --verbose {{OVERRIDES}} {{args}}
    fi

[group("Debugging")]
switch-boot-debug auth="":
    #!/usr/bin/env bash
    if [ "{{auth}}" = "sudo" ] || [ "{{auth}}" = "preauth" ] || [ "{{auth}}" = "auth" ]; then
        sudo -v
        while true; do sudo -nv; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        trap 'kill $SUDO_PID 2>/dev/null || true' EXIT
    fi
    echo "👢 Debugging bootloader generation..."
    {{LOCK_CMD}} nh os boot . -- --show-trace --verbose {{OVERRIDES}}

[group("Development")]
sys-plan:
    @echo "📋 Reviewing system derivation changes..."
    @{{LOCK_CMD}} nix build .#nixosConfigurations.nixos-nvme.config.system.build.toplevel --no-link --print-out-paths {{OVERRIDES}} > /tmp/new-system
    @{{LOCK_CMD}} nvd diff /run/current-system $(cat /tmp/new-system)

[group("Development")]
build-pkg pkg_name:
    @echo "📦 Building package: {{pkg_name}}..."
    @{{LOCK_CMD}} {{TIMER}} nix build .#{{pkg_name}} {{OVERRIDES}}

[group("Development")]
test-integration *args="":
    @echo "🧪 Running ALL integration tests..."
    @{{LOCK_CMD}} {{TIMER}} nix flake check . --system x86_64-linux {{OVERRIDES}} {{args}}

[group("Development")]
test-caddy *args="":
    @echo "🧪 Running TARGETED Caddy integration test..."
    @{{LOCK_CMD}} nix build .#checks.x86_64-linux.caddy-test {{OVERRIDES}} {{args}}

[group("Development")]
test-recovery *args="":
    @echo "🧪 Running Recovery & Restore integration test..."
    @{{LOCK_CMD}} nix build .#checks.x86_64-linux.recovery-test {{OVERRIDES}} {{args}}

[group("Development")]
test-vm *args="":
    @echo "🖥️ Building and launching test VM..."
    @{{LOCK_CMD}} {{TIMER}} nix build .#nixosConfigurations.nixos-nvme.config.system.build.vm {{OVERRIDES}} {{args}}
    @mkdir -p /var/lib/qemu/images
    NIX_DISK_IMAGE=/var/lib/qemu/images/nixos-nvme.qcow2 ./result/bin/run-nixos-nvme-vm

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
    @{{LOCK_CMD}} nh os switch . -- {{OVERRIDES}} {{args}}

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

[group("System")]
attic-token:
    @echo "🔑 Generating new Attic Admin Token (Valid for 1y)..."
    #!/usr/bin/env bash
    sudo nixos-container run attic -- sh -c ' \
      set -a; \
      . /etc/atticd-env; \
      if [ -z "$ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64" ]; then \
        export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="$ATTIC_SERVER_TOKEN_RS256_SECRET"; \
      fi; \
      ATTICADM=$(ls -1 /nix/store/*-attic-*/bin/atticadm | head -n 1); \
      CONFIG=$(ls -1 /nix/store/*-checked-attic-server.toml | head -n 1); \
      $ATTICADM -f $CONFIG make-token --sub "admin" --validity "1y" --pull "*" --push "*" --create-cache "*" --configure-cache "*" --configure-cache-retention "*" --destroy-cache "*" \
    '

# Mint a LEAST-PRIVILEGE Attic token for CI (push/pull on one cache only — no
# create/configure/destroy). Use this for the ATTIC_PUSH_TOKEN stored in CI,
# NOT the admin token above. Pipe into sops, e.g.:
#   TOKEN=$(just nixos::attic-ci-token | grep '^eyJ')
#   sops --set "[\"attic_push_token\"] \"$TOKEN\"" nix-secrets/secrets.yaml
# Usage: just nixos::attic-ci-token                  # github-ci, system, 1y
#        just nixos::attic-ci-token github-ci system 10y
[group("System")]
attic-ci-token sub="github-ci" cache="system" validity="1y":
    #!/usr/bin/env bash
    set -euo pipefail
    sudo nixos-container run attic -- sh -c '
      set -a; . /etc/atticd-env
      [ -z "${ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64:-}" ] && \
        export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="$ATTIC_SERVER_TOKEN_RS256_SECRET"
      ATTICADM=$(ls -1 /nix/store/*-attic-*/bin/atticadm | head -n 1)
      CONFIG=$(ls -1 /nix/store/*-checked-attic-server.toml | head -n 1)
      "$ATTICADM" -f "$CONFIG" make-token \
        --sub "{{ sub }}" --validity "{{ validity }}" --pull "{{ cache }}" --push "{{ cache }}"
    '
