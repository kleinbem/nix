#!/usr/bin/env bash
# Workspace Hub — a linutil-style, fleet-aware browser over `just` recipes.
#
# This is a READ-ONLY OVERLAY. It never moves or redefines recipes: the
# multi-justfile layout is deliberate (each repo owns the recipes relevant to
# it). The hub discovers recipes in place via `just --summary` and dispatches
# them back to the repo where they live:
#   - meta-root recipes      →  just <recipe>
#   - nix-config recipes     →  just in nix-config <recipe>
#
# Navigation is a two-level tree (linutil-like):
#   Level 1: categories  (⭐ Common, 🚢 By Host, then one per module prefix)
#   Level 2: the recipes inside the chosen category, with a ⬅ back entry.
#
# fzf preview/edit re-exec THIS script with a --preview-*/--edit-recipe
# subcommand, inheriting the built index via the exported $INDEX env var, so
# no per-keystroke rebuild and no dependence on exported shell functions.
#
# Requires: fzf, just. Runs from the meta-workspace root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$ROOT/tools/workspace-hub.sh"
cd "$ROOT"
TAB=$'\t'

# --- Build the recipe index: source <TAB> category <TAB> recipe -------------
# Meta-root recipes and nix-config recipes are both enumerated in place.
build_index() {
  just --summary 2>/dev/null | tr ' ' '\n' | while read -r r; do
    [ -z "$r" ] && continue
    case "$r" in
    *::*) cat="${r%%::*}" ;;
    *) cat="workspace" ;;
    esac
    printf 'meta\t%s\t%s\n' "$cat" "$r"
  done

  (cd nix-config && just --summary 2>/dev/null) | tr ' ' '\n' | while read -r r; do
    [ -z "$r" ] && continue
    case "$r" in
    *::*) cat="${r%%::*}" ;;
    *) cat="config" ;;
    esac
    printf 'nix-config\t%s\t%s\n' "$cat" "$r"
  done
}

icon_for() {
  case "$1" in
  android) echo "📱" ;;
  jj) echo "🔄" ;;
  nixos) echo "🏗️" ;;
  ai) echo "🤖" ;;
  devshell) echo "💻" ;;
  deployment) echo "🚀" ;;
  maintenance) echo "🧹" ;;
  orin) echo "🏎️" ;;
  core-pi) echo "🥧" ;;
  hass-pi) echo "🏠" ;;
  nasbook) echo "💾" ;;
  dev) echo "🔧" ;;
  extensions) echo "🧩" ;;
  personas) echo "🎭" ;;
  workspace | config) echo "✨" ;;
  __common__) echo "⭐" ;;
  __byhost__) echo "🚢" ;;
  *) echo "🛠️" ;;
  esac
}

# --- Curated "Common" set (source<TAB>recipe<TAB>label) ---------------------
common_entries() {
  printf 'meta\tapply\tapply — align → switch\n'
  printf 'meta\tswitch\tswitch — raw nixos-rebuild\n'
  printf 'meta\tstatus-all\tstatus-all — jj dashboard\n'
  printf 'meta\tcheck\tcheck — eval primary host\n'
  printf 'nix-config\tdeployment::deploy-fleet\tdeploy-fleet — colmena push\n'
}

# --- Host → (module prefix, deployment token) -------------------------------
HOSTS=(orin-nano core-pi hass-pi nasbook nixos-nvme)
host_prefix() { case "$1" in
  orin-nano) echo orin ;; core-pi) echo core-pi ;; hass-pi) echo hass-pi ;;
  nasbook) echo nasbook ;; nixos-nvme) echo nixos ;; esac }
host_token() { case "$1" in
  orin-nano) echo orin ;; core-pi) echo core ;; hass-pi) echo hass ;;
  nasbook) echo nasbook ;; nixos-nvme) echo __none__ ;; esac }

# Emit the recipes belonging to a host: its module prefix + matching deployments.
host_entries() {
  local host="$1" pfx tok
  pfx="$(host_prefix "$host")"
  tok="$(host_token "$host")"
  awk -F"$TAB" -v pfx="$pfx" -v tok="$tok" '
        $2 == pfx { print; next }
        $2 == "deployment" && tok != "__none__" && index($3, tok) { print }
    ' "$INDEX"
}

# --- Helpers invoked both inline and via re-exec subcommands -----------------
dispatch() { # dispatch <source> <recipe>
  local src="$1" rec="$2"
  echo "▶ $rec  (${src})"
  if [ "$src" = "nix-config" ]; then just in nix-config "$rec"; else just "$rec"; fi
}

show_recipe() { # show_recipe <source> <recipe> — used by fzf preview
  local src="$1" rec="$2"
  { [ "$src" = "nix-config" ] && (cd nix-config && just --show "$rec"); } ||
    just --show "$rec" 2>/dev/null ||
    echo "(no preview)"
}

preview_category() { # preview_category <category-key> — used by fzf preview
  case "$1" in
  __common__) echo "apply · switch · status-all · check · deploy-fleet" ;;
  __byhost__) echo "Pick a host to see its recipes + matching deploys." ;;
  *) awk -F"$TAB" -v c="$1" '$2==c{print "• "$3"  ["$1"]"}' "$INDEX" ;;
  esac
}

edit_recipe() { # edit_recipe <source> <recipe> — best effort, used by Ctrl-E
  local src="$1" rec="$2" bare dir hit
  bare="${rec##*::}"
  dir="$ROOT"
  [ "$src" = "nix-config" ] && dir="$ROOT/nix-config"
  # Prefer module files (.just/*) so `foo::bar` opens its module definition,
  # falling back to the top-level justfile for un-prefixed recipes.
  hit="$(grep -rniE "^${bare}( |:)" "$dir/.just" 2>/dev/null | head -1)"
  [ -z "$hit" ] && hit="$(grep -niE "^${bare}( |:)" "$dir/justfile" 2>/dev/null | sed "s|^|$dir/justfile:|" | head -1)"
  if [ -n "$hit" ]; then
    local file line
    file="${hit%%:*}"
    line="$(echo "$hit" | cut -d: -f2)"
    "${EDITOR:-nano}" "+$line" "$file"
  else
    "${EDITOR:-nano}" "$dir/justfile"
  fi
}

# --- Re-exec subcommands (fzf preview/edit call back into this script) -------
# These inherit $INDEX from the parent process's environment; they must run
# before the interactive path so no index rebuild happens per keystroke.
case "${1:-}" in
--preview-category)
  preview_category "$2"
  exit 0
  ;;
--preview-recipe)
  show_recipe "$2" "$3"
  exit 0
  ;;
--edit-recipe)
  edit_recipe "$2" "$3"
  exit 0
  ;;
esac

# --- Level 2: pick a recipe from a pre-built entry list ---------------------
# stdin: lines of  source<TAB>recipe<TAB>label
pick_recipe() {
  local title="$1" entries sel src rec
  entries="$(cat)"
  [ -z "$entries" ] && {
    echo "  (no recipes here)"
    sleep 1
    return 1
  }

  # Prepend a back row; display column shows icon+label.
  sel="$(
    {
      printf '__back__\t__back__\t⬅  back\n'
      echo "$entries" | while IFS="$TAB" read -r s r l; do
        printf '%s\t%s\t%s %s\n' "$s" "$r" "$(icon_for "${r%%::*}")" "$l"
      done
    } | fzf --delimiter="$TAB" --with-nth=3 --ansi --reverse --border \
      --height=90% --margin=1,2 --info=inline --pointer="➜" \
      --header "$title | [Enter] run · [Ctrl-E] edit · [Esc] back" \
      --prompt "🔍 " \
      --color "header:italic:cyan,prompt:yellow,pointer:red" \
      --preview "bash $SELF --preview-recipe {1} {2}" \
      --preview-window "right:58%:wrap" \
      --bind "ctrl-e:execute(bash $SELF --edit-recipe {1} {2})"
  )" || return 1
  [ -z "$sel" ] && return 1

  src="$(echo "$sel" | cut -f1)"
  rec="$(echo "$sel" | cut -f2)"
  [ "$src" = "__back__" ] && return 1
  dispatch "$src" "$rec"
  return 0 # a recipe ran → leave the hub
}

# --- Level 1: categories ----------------------------------------------------
main_menu() {
  local cats sel key host
  # Real categories with counts, ordered by count desc.
  cats="$(awk -F"$TAB" '{print $2}' "$INDEX" | sort | uniq -c | sort -rn |
    awk '{print $2"\t"$1}')"

  while true; do
    sel="$(
      {
        printf '__common__\t⭐ Common          curated everyday actions\n'
        printf '__byhost__\t🚢 By Host         orin · core-pi · hass-pi · nasbook · nixos-nvme\n'
        echo "$cats" | while IFS="$TAB" read -r c n; do
          printf '%s\t%s %-14s (%s)\n' "$c" "$(icon_for "$c")" "$c" "$n"
        done
      } | fzf --delimiter="$TAB" --with-nth=2 --ansi --reverse --border \
        --height=90% --margin=1,2 --info=inline --pointer="➜" \
        --header "🚢 Workspace Hub — pick a category | [Esc] quit" \
        --prompt "🔍 " \
        --color "header:italic:cyan,prompt:yellow,pointer:red" \
        --preview "bash $SELF --preview-category {1}" \
        --preview-window "right:58%:wrap"
    )" || return 0 # Esc at top level → quit

    [ -z "$sel" ] && return 0
    key="$(echo "$sel" | cut -f1)"

    case "$key" in
    __common__)
      common_entries | pick_recipe "⭐ Common" && return 0
      ;;
    __byhost__)
      host="$(printf '%s\n' "${HOSTS[@]}" | fzf --reverse --border --height=60% \
        --header "🚢 Pick a host | [Esc] back" --prompt "🔍 ")" || continue
      [ -z "$host" ] && continue
      host_entries "$host" |
        awk -F"$TAB" '{print $1"\t"$3"\t"$3}' |
        pick_recipe "🚢 $host" && return 0
      ;;
    *)
      awk -F"$TAB" -v c="$key" '$2==c{print $1"\t"$3"\t"$3}' "$INDEX" |
        pick_recipe "$(icon_for "$key") $key" && return 0
      ;;
    esac
  done
}

# --- Interactive entrypoint -------------------------------------------------
command -v fzf >/dev/null || {
  echo "❌ fzf not found (enter the workspace devshell)"
  exit 1
}
INDEX="$(mktemp)"
export INDEX
trap 'rm -f "$INDEX"' EXIT
build_index | sort -u >"$INDEX"
main_menu
