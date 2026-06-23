#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: lets <task> [args...]" >&2
  exit 1
fi

case "$1" in
-h | --help)
  set -- help "${@:2}"
  ;;
-s | --show)
  set -- show "${@:2}"
  ;;
-v | --version)
  printf '\n\033[1;36m lets - A Nix Task Runner\033[0m\n'
  printf '\033[2m-------------------------\033[0m\n\n'
  printf ' Version    %s\n' "$VERSION"
  printf ' Repository %s\n' 'https://github.com/JeffDess/lets'
  echo
  exit 0
  ;;
esac

is_target() {
  local t
  for t in "${TARGETS[@]}"; do
    [ "$t" = "$1" ] && return 0
  done
  return 1
}

target=""
consumed=0
candidate=""
count=0
for tok in "$@"; do
  case "$tok" in
  -*) break ;;
  esac
  if [ -z "$candidate" ]; then
    candidate="$tok"
  else
    candidate="${candidate}_${tok}"
  fi
  count=$((count + 1))
  if is_target "$candidate"; then
    target="$candidate"
    consumed="$count"
  fi
done

if [ -z "$target" ]; then
  echo "Error: unknown task: $1" >&2
  exit 1
fi

shift "$consumed"
exec nix run --option warn-dirty false .#"$target" -- "$@"
