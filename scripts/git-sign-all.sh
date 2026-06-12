#!/usr/bin/env bash
# scripts/git-sign-all.sh
# Squashes and signs unpushed commits in the workspace to satisfy GitHub verified signature rules.

set -euo pipefail

# Colors
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

# Get root directory of the workspace
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Read repos from common.just (nix-* folders in root)
mapfile -t REPOS < <(find "$ROOT_DIR" -maxdepth 1 -name 'nix-*' -type d -printf '%f\n' | sort)
# Add root repo to the list
REPOS+=(".")

echo -e "${BOLD}${CYAN}🔑 Git Workspace Signature Sync...${RESET}\n"

has_unsigned=0

for repo_dir in "${REPOS[@]}"; do
  if [ "$repo_dir" = "." ]; then
    path="$ROOT_DIR"
    name="workspace-root"
  else
    path="$ROOT_DIR/$repo_dir"
    name="$repo_dir"
  fi

  if [ ! -d "$path/.git" ] && [ ! -f "$path/.git" ]; then
    continue
  fi

  # Determine default branch
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

  # Check if remote exists
  if ! git -C "$path" rev-parse --verify "origin/$branch" &>/dev/null; then
    continue
  fi

  # Count unpushed commits
  unpushed_count=$(git -C "$path" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)
  if [ "$unpushed_count" -eq 0 ]; then
    continue
  fi

  # Find which of these commits are unsigned
  unsigned_list=()
  for commit in $(git -C "$path" rev-list "origin/$branch..HEAD"); do
    if ! git -C "$path" log -n 1 --show-signature "$commit" 2>/dev/null | grep -q 'Good "git" signature'; then
      unsigned_list+=("$commit")
    fi
  done

  unsigned_count=${#unsigned_list[@]}
  if [ "$unsigned_count" -eq 0 ]; then
    echo -e "🟢 Repository ${BOLD}${name}${RESET} is ahead by ${unpushed_count} commits (${GREEN}all signed${RESET})."
    continue
  fi

  echo -e "📦 Repository ${BOLD}${name}${RESET} has ${RED}${unsigned_count}${RESET} unsigned commits (out of ${unpushed_count} unpushed)."

  # Check if all unsigned commits are purely lockfile updates
  # We get the messages for only the unsigned commits
  is_pure_lockfiles=1
  for commit in "${unsigned_list[@]}"; do
    msg=$(git -C "$path" log -n 1 --format="%s" "$commit")
    if [[ ! $msg =~ ^chore:\ (auto-update\ lockfile|update\ flake\ lockfiles|update\ workspace) ]]; then
      is_pure_lockfiles=0
      break
    fi
  done

  if [ "$is_pure_lockfiles" -eq 1 ]; then
    echo -e "  🧹 Only unsigned lockfile updates detected. ${GREEN}Squashing into 1 signed commit...${RESET}"
    # Soft reset to remote state
    git -C "$path" reset --soft "origin/$branch"
    # Commit manually (will sign using user's config, bypassing buggy ssh-agent)
    env SSH_AUTH_SOCK= git -C "$path" commit -m "chore: auto-update lockfile"
    echo -e "  ✅ Squashed and signed!"
  else
    echo -e "  ⚠️ Unsigned manual commits detected."
    echo -e "  Unsigned commits:"
    for commit in "${unsigned_list[@]}"; do
      msg=$(git -C "$path" log -n 1 --format="%h %s" "$commit")
      echo -e "    ${RED}✗${RESET} $msg"
    done
    echo -e "  Run one of the following to resolve:"
    if [ "$repo_dir" = "." ]; then
      echo -e "    • Squash all unpushed into 1 signed commit: ${BOLD}git reset --soft origin/$branch && git commit -m \"<message>\"${RESET}"
      echo -e "    • Re-sign commits (preserving history): ${BOLD}git rebase --exec \"git commit --amend --no-edit\" origin/$branch${RESET}"
    else
      echo -e "    • Squash all unpushed into 1 signed commit: ${BOLD}git -C $repo_dir reset --soft origin/$branch && git -C $repo_dir commit -m \"<message>\"${RESET}"
      echo -e "    • Re-sign commits (preserving history): ${BOLD}git -C $repo_dir rebase --exec \"git commit --amend --no-edit\" origin/$branch${RESET}"
    fi
    has_unsigned=1
  fi
  echo ""
done

if [ "$has_unsigned" -eq 1 ]; then
  echo -e "${RED}❌ Please resolve the unsigned manual commits listed above before pushing.${RESET}"
  exit 1
fi

echo -e "✨ ${BOLD}${GREEN}All repositories are fully signed and ready to push!${RESET}"
exit 0
