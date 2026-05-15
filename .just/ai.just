import 'common.just'

set working-directory := ".."

# --- AI & Agentic Hub ---

[group("Status")]
ai-sync:
    @echo "🔄 Syncing Agentic Hub documentation..."
    @for repo in {{REPOS}}; do \
        if [ -d "$repo/.agent/knowledge" ]; then \
            echo "Pulling knowledge from $repo..."; \
            rsync -av --delete $repo/.agent/knowledge/ .agent/knowledge/$repo/ 2>/dev/null || true; \
        fi \
    done

[group("Knowledge")]
ai-distill title="unnamed-session":
    @echo "🧠 Distilling knowledge into permanence: {{title}}"
    @git diff HEAD | nix run nixpkgs#llm -- "Summarize these changes into a technical knowledge item for the meta-repo." > .agent/knowledge/distilled-{{title}}.md

[group("Status")]
ai-check:
    @echo "🩺 AI Stack Health Check"
    @curl -s http://localhost:11434/api/tags >/dev/null && echo "✅ Ollama: Online" || echo "❌ Ollama: Offline"
    @curl -s http://localhost:8000/health >/dev/null && echo "✅ vLLM: Online" || echo "❌ vLLM: Offline"

[group("Coding")]
architect:
    @echo "🏗️ Launching Aider (Architect Mode)..."
    @aider --model gemini/gemini-2.0-flash-thinking-exp --architect

[group("Coding")]
code:
    @echo "⚡ Launching Aider (DeepSeek)..."
    @aider --model deepseek/deepseek-chat

[group("Coding")]
plan:
    @echo "📋 Launching Aider (Gemini Pro)..."
    @aider --model gemini/gemini-pro

[group("Coding")]
local:
    @echo "🏠 Launching Aider (Local via Ollama)..."
    @aider --model openai/ollama/llama3 --openai-api-base http://localhost:11434/v1

[group("Development")]
ai-shell:
    @echo "🐚 Entering AI DevShell..."
    @nix develop .#ai

[group("Debugging")]
ai-logs *args:
    @journalctl -p 3 -n 50 --no-pager {{args}} | nix run nixpkgs#llm -- "Explain these errors in simple terms and suggest fixes."

[group("Debugging")]
ai-team-logs:
    @echo "👥 Viewing Agent Team activity..."
    @tail -f /var/log/agent-team.log

[group("Workflow")]
ai-init-safe:
    @echo "🌡️ Starting AI stack in Safe Mode..."
    @systemctl start ollama.service
    @sleep 5
    @systemctl start vllm.service
    @echo "✅ AI Stack Ready."

[group("Development")]
ai-provision-models:
    @echo "📥 Pulling recommended local models..."
    @ollama pull nomic-embed-text
    @ollama pull llama3:8b

[group("Status")]
ai-health-fleet:
    @just ai::ai-check
    @echo "📡 Probing Orin Nano..."
    @just deployment::orin-ping && echo "✅ Orin: Reachable" || echo "❌ Orin: Unreachable"

[group("Knowledge")]
distill:
    @echo "🧪 Distilling conversation history..."
    @python3 ./scripts/rebuild_history.py --distill
