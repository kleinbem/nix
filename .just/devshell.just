# --- Isolated DevShells (Evaluative Isolation) ---
# These shells evaluate independently from nixos::switch.
# Most shells live in nix-devshells; `ultimate` is a meta-flake composite.

[group("Shells")]
pentest:
    @echo "🔓 Entering Pentesting Shell..."
    @nix develop ./nix-devshells#pentest

[group("Shells")]
ai-dev:
    @echo "🤖 Entering AI Dev Shell..."
    @nix develop ./nix-devshells#ai-dev

[group("Shells")]
math:
    @echo "🧮 Entering Math Shell..."
    @nix develop ./nix-devshells#math

[group("Shells")]
media:
    @echo "🎬 Entering Media Shell..."
    @nix develop ./nix-devshells#media

[group("Shells")]
apps:
    @echo "🏢 Entering Productivity Apps Shell..."
    @nix develop ./nix-devshells#apps

[group("Shells")]
ultimate:
    @echo "🌌 Entering Ultimate DevShell..."
    @nix develop .#ultimate

[group("Shells")]
arm:
    @echo "📱 Entering ARM-Specific Shell..."
    @nix develop ./nix-devshells#arm

[group("Shells")]
android:
    @echo "🤖 Entering Android DevShell..."
    @nix develop ./nix-devshells#android
