import 'common.just'

set working-directory := ".."

# --- Git Operations ---

[group("Status")]
status:
    @echo "📊 Workspace Status Dashboard"
    @printf "%-30s %-20s %-10s\n" "REPOSITORY" "BRANCH" "STATUS"
    @printf "%-30s %-20s %-10s\n" "------------------------------" "--------------------" "----------"
    @for repo in {{REPOS}}; do \
        branch=$(git -C $repo rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A"); \
        status=$(git -C $repo status --short 2>/dev/null | head -n 1); \
        if [ -n "$status" ]; then color="\033[0;31m"; status_text="DIRTY"; \
        else color="\033[0;32m"; status_text="CLEAN"; fi; \
        printf "%-30s %-20s ${color}%-10s\033[0m\n" "$repo" "$branch" "$status_text"; \
    done

[group("Sync")]
stage-all:
    @echo "📦 Staging all changes across workspace..."
    @for repo in {{REPOS}}; do \
        git -C $repo add .; \
    done
    @git add .


[group("Sync")]
pull:
    @echo "📥 Pulling latest changes for all repositories..."
    @for repo in {{REPOS}}; do \
        echo "Updating $repo..."; \
        git -C $repo pull --rebase; \
    done

[group("Sync")]
save message:
    @echo "💾 Saving workspace state: {{message}}"
    @for repo in {{REPOS}}; do \
        if [ -n "$(git -C $repo status --short)" ]; then \
            echo "Committing in $repo..."; \
            git -C $repo add .; \
            git -C $repo commit -m "{{message}}"; \
        fi \
    done
    @git add .
    @git commit -m "chore: update workspace ({{message}})"
    @echo "✅ Workspace state saved."

[group("Sync")]
push:
    @./scripts/git-sign-all.sh
    @echo "📤 Pushing all changes..."
    @for repo in {{REPOS}}; do \
        git -C $repo push; \
    done
    @git push

[group("Sync")]
[confirm("⚠️ This will HARD RESET all repositories to origin/main. Continue?")]
sync:
    @echo "🔄 Synchronizing all workspace modules..."
    @git submodule sync --recursive
    @git submodule update --init --recursive
    @for repo in {{REPOS}}; do \
        git -C $repo fetch --all; \
        git -C $repo checkout main; \
        git -C $repo reset --hard origin/main; \
    done
    @echo "✅ Workspace synchronized."

[group("Security")]
git-sign:
    @echo "🔑 Loading YubiKey for Git signing..."
    @ssh-add -e /usr/lib/libtpm2_pkcs11.so 2>/dev/null || true
    @ssh-add -s /usr/lib/libtpm2_pkcs11.so 2>/dev/null || true
    @echo "✅ Ready to sign."

[group("Development")]
[confirm("🌿 This will create a new branch in ALL repositories. Continue?")]
branch name:
    @echo "🌿 Creating branch '{{name}}' across workspace..."
    @git checkout -b {{name}}
    @for repo in {{REPOS}}; do \
        git -C $repo checkout -b {{name}}; \
    done
