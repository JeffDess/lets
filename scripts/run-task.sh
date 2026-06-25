#!/usr/bin/env bash

set -euo pipefail

if [ "${1:-}" = "__complete" ]; then
  shift
  argc=$#
  if [ "$argc" -ge 1 ]; then cur="${!argc}"; else cur=""; fi
  if [ "$argc" -ge 2 ]; then
    __p=$((argc - 1))
    prev="${!__p}"
  else prev=""; fi

  path="lets"
  pathlen=0
  __i=2
  while [ "$__i" -lt "$argc" ]; do
    tok="${!__i}"
    case "$tok" in -*) break ;; esac
    cand="$path $tok"
    if [ -n "${_LETS_NODE[$cand]+x}" ]; then
      path="$cand"
      pathlen=$((pathlen + 1))
    else
      break
    fi
    __i=$((__i + 1))
  done

  emit() {
    if [ -n "${1:-}" ]; then printf '%s\n' "$1"; fi
    return 0
  }

  key="${path}##${prev}"
  if [ -n "${_LETS_OPTNEEDS[$key]+x}" ]; then
    emit "${_LETS_OPTVAL[$key]:-}"
    exit 0
  fi

  case "$cur" in
  -*)
    emit "${_LETS_OPT[$path]:-}"
    ;;
  *)
    emit "${_LETS_SUB[$path]:-}"
    if [ "$argc" -eq $((pathlen + 2)) ]; then
      emit "${_LETS_POSVAL[$path]:-}"
    fi
    ;;
  esac
  exit 0
fi

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
-c | --completions)
  shift
  exec nix run --option warn-dirty false .#completions -- "$@"
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
