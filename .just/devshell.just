# --- Isolated DevShells (Evaluative Isolation) ---
# These shells evaluate independently from nixos::switch.

[group("Shells")]
pentest:
    @echo "🔓 Entering Pentesting Shell..."
    @nix develop .#pentest

[group("Shells")]
ai-dev:
    @echo "🤖 Entering AI Dev Shell..."
    @nix develop .#ai-dev

[group("Shells")]
math:
    @echo "🧮 Entering Math Shell..."
    @nix develop .#math

[group("Shells")]
media:
    @echo "🎬 Entering Media Shell..."
    @nix develop .#media

[group("Shells")]
apps:
    @echo "🏢 Entering Productivity Apps Shell..."
    @nix develop .#apps

[group("Shells")]
ultimate:
    @echo "🌌 Entering Ultimate DevShell..."
    @nix develop .#ultimate

[group("Shells")]
arm:
    @echo "📱 Entering ARM-Specific Shell..."
    @nix develop .#arm

[group("Shells")]
android:
    @echo "🤖 Entering Android DevShell..."
    @nix develop .#android
