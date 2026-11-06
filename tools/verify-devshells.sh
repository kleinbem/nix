#!/usr/bin/env bash
# Build every devshell to catch eval errors and missing dependencies.
# No `set -e`: every shell is built and reported, even after a failure.

# Shells to verify, keyed by flake. All shells live in nix-devshells.
META_SHELLS=("workspace" "ultimate")
DEVSHELL_SHELLS=("apps" "pentest" "ai-dev" "math" "media" "android" "arm")

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CURRENT_SYSTEM=$(nix eval --raw --impure --expr 'builtins.currentSystem')

echo -e "${YELLOW}🧪 Verifying DevShell Evaluation on ${CURRENT_SYSTEM}...${NC}"
echo "------------------------------------------------------------"
printf "%-15s | %-10s | %-30s\n" "Shell" "Status" "Details/Error"
failed=0
echo "------------------------------------------------------------"

verify_one() {
  local flake_ref="$1"
  local shell="$2"
  if nix build "${flake_ref}#devShells.${CURRENT_SYSTEM}.${shell}" --no-link --print-build-logs >verify_shell.log 2>&1; then
    printf "${GREEN}✅ %-13s${NC} | OK         | -\n" "$shell"
  else
    ERROR=$(grep -E "error:" verify_shell.log | head -n 1 | sed 's/error: //')
    if [ -z "$ERROR" ]; then
      ERROR="Evaluation failed (check verify_shell.log)"
    fi
    printf "${RED}❌ %-13s${NC} | FAILED     | %-30s\n" "$shell" "$ERROR"
    failed=$((failed + 1))
  fi
}

for shell in "${META_SHELLS[@]}"; do
  verify_one "../nix-devshells" "$shell"
done
for shell in "${DEVSHELL_SHELLS[@]}"; do
  verify_one "../nix-devshells" "$shell"
done

rm -f verify_shell.log
echo "------------------------------------------------------------"
echo -e "${YELLOW}Tip: Use 'just devshell::<shell>' or 'nix develop ../nix-devshells#<shell>' to debug.${NC}"
[ "$failed" -eq 0 ] || exit 1
