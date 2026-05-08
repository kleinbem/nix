#!/usr/bin/env bash
# scripts/verify-devshells.sh
# Verifies all defined devshells by attempting to build their derivations.
# This catches evaluation errors and missing dependencies.

# List of shells to verify (from root flake.nix)
SHELLS=("default" "apps" "pentest" "ai-dev" "math" "media" "ultimate")

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧪 Verifying DevShell Evaluation...${NC}"
echo "------------------------------------------------------------"
printf "%-15s | %-10s | %-30s\n" "Shell" "Status" "Details/Error"
echo "------------------------------------------------------------"

for shell in "${SHELLS[@]}"; do
    # Capture only the error message if it fails
    # We use --no-link to avoid creating 'result' symlinks
    if nix build .#devShells.x86_64-linux."$shell" --no-link --print-build-logs > verify_shell.log 2>&1; then
        printf "${GREEN}✅ %-13s${NC} | OK         | -\n" "$shell"
    else
        # Extract the most relevant error line
        ERROR=$(grep -E "error:" verify_shell.log | head -n 1 | sed 's/error: //')
        if [ -z "$ERROR" ]; then
            ERROR="Evaluation failed (check verify_shell.log)"
        fi
        printf "${RED}❌ %-13s${NC} | FAILED     | %-30s\n" "$shell" "$ERROR"
    fi
done

rm -f verify_shell.log
echo "------------------------------------------------------------"
echo -e "${YELLOW}Tip: Use 'nix develop .#<shell>' to debug specific failures.${NC}"
