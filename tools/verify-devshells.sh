#!/usr/bin/env bash
# tools/verify-devshells.sh
# Verifies all defined devshells by attempting to build their derivations.
# This catches evaluation errors and missing dependencies.
#
# NOTE: deliberately no `set -e` — the script's contract is to run EVERY
# shell's build attempt and report success/failure per shell. Bailing on
# the first failure would defeat its purpose.

# Shells to verify, keyed by flake. All shells live in nix-devshells.
META_SHELLS=("workspace" "ultimate")
DEVSHELL_SHELLS=("apps" "pentest" "ai-dev" "math" "media" "android" "arm")


# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧪 Verifying DevShell Evaluation...${NC}"
echo "------------------------------------------------------------"
printf "%-15s | %-10s | %-30s\n" "Shell" "Status" "Details/Error"
echo "------------------------------------------------------------"

verify_one() {
  local flake_ref="$1"
  local shell="$2"
  if nix build "${flake_ref}#devShells.x86_64-linux.${shell}" --no-link --print-build-logs >verify_shell.log 2>&1; then
    printf "${GREEN}✅ %-13s${NC} | OK         | -\n" "$shell"
  else
    ERROR=$(grep -E "error:" verify_shell.log | head -n 1 | sed 's/error: //')
    if [ -z "$ERROR" ]; then
      ERROR="Evaluation failed (check verify_shell.log)"
    fi
    printf "${RED}❌ %-13s${NC} | FAILED     | %-30s\n" "$shell" "$ERROR"
  fi
}

for shell in "${META_SHELLS[@]}"; do
  verify_one "./nix-devshells" "$shell"
done
for shell in "${DEVSHELL_SHELLS[@]}"; do
  verify_one "./nix-devshells" "$shell"
done

rm -f verify_shell.log
echo "------------------------------------------------------------"
echo -e "${YELLOW}Tip: Use 'just devshell::<shell>' or 'nix develop ./nix-devshells#<shell>' to debug.${NC}"
