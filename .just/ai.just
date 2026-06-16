import 'common.just'

set working-directory := ".."

# --- AI tooling (meta-workspace concerns: knowledge management, Aider launchers) ---
# Host-side AI operations (service health, model provisioning, agent logs)
# live in `nix-config/.just/ai.just`.

[group("Knowledge")]
knowledge-sync:
    @echo "🔄 Syncing Agentic Hub documentation..."
    @for repo in {{REPOS}}; do \
        if [ -d "$repo/.agent/knowledge" ]; then \
            echo "Pulling knowledge from $repo..."; \
            rsync -av --delete $repo/.agent/knowledge/ .agent/knowledge/$repo/ 2>/dev/null || true; \
        fi \
    done

[group("Knowledge")]
distill-session title="unnamed-session":
    @echo "🧠 Distilling knowledge into permanence: {{title}}"
    @jj diff | nix run nixpkgs#llm -- "Summarize these changes into a technical knowledge item for the meta-repo." > .agent/knowledge/distilled-{{title}}.md

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

[group("Knowledge")]
distill:
    @echo "🧪 Distilling conversation history..."
    @python3 ./scripts/rebuild_history.py --distill
