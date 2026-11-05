#!/usr/bin/env bash
# Plan, refuse planned deletes or replacements, then apply exactly that plan.
# Run from an initialized root with its backend/encryption env already set.
#   tofu-guarded-apply.sh [--auto-approve] [tofu plan args...]
#   ALLOW_DESTROY=1  apply even when the plan deletes or replaces something
set -euo pipefail

auto=0
args=()
for a in "$@"; do
  case "$a" in
  -auto-approve | --auto-approve) auto=1 ;;
  # The guard applies only the plan it checked.
  -out | -out=* | --out | --out=*)
    echo "❌ -out isn't supported here: the guarded plan is applied directly." >&2
    exit 2
    ;;
  *) args+=("$a") ;;
  esac
done

# The plan holds variable values (secrets): keep it in RAM where there is one.
tmpbase=/tmp
[ -d /dev/shm ] && tmpbase=/dev/shm
work=$(mktemp -d "$tmpbase/tofu-plan-XXXXXX")
trap 'rm -rf "$work"' EXIT

tofu plan -input=false -out="$work/plan" "${args[@]}"

destroys=$(tofu show -json "$work/plan" | jq -r '
  .resource_changes[]? | select(.change.actions | index("delete"))
  | "\(.address) (\(.change.actions | join(" then ")))"')
if [ -n "$destroys" ]; then
  echo "⚠️  The plan deletes or replaces:" >&2
  printf '   %s\n' "$destroys" >&2
  if [ "${ALLOW_DESTROY:-}" != 1 ]; then
    echo "❌ Refusing to apply. Re-run with ALLOW_DESTROY=1 if that's intended." >&2
    exit 1
  fi
  echo "ALLOW_DESTROY=1 set: going ahead." >&2
fi

if [ "$auto" -eq 0 ]; then
  read -r -p "Apply this plan? [y/N] " answer
  [[ "$answer" == [yY]* ]] || { echo "Not applied."; exit 1; }
fi
tofu apply -input=false "$work/plan"
