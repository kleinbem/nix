# Orin Nano Operations
import 'common.just'

set working-directory := ".."

[group("Orin")]
stats:
    @echo "📊 Opening Jetson Hardware Monitor..."
    jtop

[group("Orin")]
desktop:
    @echo "🖥️ Activating Lite Desktop (Sway)..."
    sudo /run/current-system/specialisation/desktop/bin/switch

[group("Orin")]
server:
    @echo "🧠 Returning to Headless AI Mode..."
    sudo /run/current-system/bin/switch-to-configuration switch

[group("Orin")]
logs-vision:
    @echo "📹 Streaming Frigate logs..."
    journalctl -u container@frigate -f

[group("Orin")]
logs-ai:
    @echo "🤖 Streaming llama-cpp logs..."
    journalctl -u container@llama-cpp -f

[group("Orin")]
ai-chat:
    @echo "💬 Opening local chat interface..."
    # Connects to the local llama-cpp endpoint
    curl -s http://localhost:8080/v1/models | jq
