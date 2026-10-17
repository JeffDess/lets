#!/usr/bin/env bash

if [ "${1:-}" = "__complete" ]; then
  shift
  argc=$#
  if [ "$argc" -ge 1 ]; then cur="${!argc}"; else cur=""; fi
  if [ "$argc" -ge 2 ]; then
    __p=$((argc - 1))
    prev="${!__p}"
  else prev=""; fi

  path="lets"
  __i=2
  while [ "$__i" -lt "$argc" ]; do
    tok="${!__i}"
    case "$tok" in
    -E | --env-file)
      [ "$path" = lets ] || break
      __i=$((__i + 1))
      ;;
    --env-file=* | --no-env-files) [ "$path" = lets ] || break ;;
    -*) break ;;
    *)
      cand="$path $tok"
      [ -n "${_LETS_NODE[$cand]+x}" ] || break
      path="$cand"
      ;;
    esac
    __i=$((__i + 1))
  done

  emit() {
    if [ -n "${1:-}" ]; then printf '%s\n' "$1"; fi
    return 0
  }

  inline=''
  case "$cur" in
  --env-file=*)
    inline="${cur%%=*}="
    prev="${cur%%=*}"
    cur="${cur#*=}"
    ;;
  esac

  if [ "$path" = lets ]; then
    case "$prev" in
    -E | --env-file)
      shopt -s nullglob dotglob
      glob="$cur"
      if [[ $cur == \~/* ]]; then glob="$HOME/${cur#\~/}"; fi
      for f in "$glob"*; do
        if [ -d "$f" ]; then f+=/; fi
        if [[ $cur == \~/* ]]; then f=\~/"${f#"$HOME"/}"; fi
        printf '%s%s\n' "$inline" "$f"
      done
      exit 0
      ;;
    esac
  fi

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
    if [ "$argc" -eq "$__i" ]; then
      emit "${_LETS_POSVAL[$path]:-}"
    fi
    ;;
  esac
  exit 0
fi

usage() {
  echo "Usage: lets [-E <file>]... [--no-env-files] <task> [args...]" >&2
  exit 1
}

if [ "$#" -lt 1 ]; then
  usage
fi

env_source() {
  export LETS_ENV_SOURCES="${LETS_ENV_SOURCES:+$LETS_ENV_SOURCES$'\n'}$1"
}

from_pwd() {
  case "$1" in
  /* | \~/* | '$'*) from_pwd="$1" ;;
  *)
    if [[ $PWD == *'$'* ]]; then
      error "cannot resolve $1: $PWD contains '\$'; use an absolute path"
      exit 1
    fi
    from_pwd="$PWD/$1"
    ;;
  esac
}

env_file() {
  case "${1:-}" in
  '')
    error "--env-file needs a file"
    exit 1
    ;;
  *$'\n'*)
    error "--env-file value cannot span lines"
    exit 1
    ;;
  esac
  from_pwd "$1"
  env_source "file:$from_pwd"
}

env_files_from_pwd() {
  local - IFS=: entry resolved=()
  set -f
  for entry in $LETS_ENV_FILES; do
    [ -n "$entry" ] || continue
    from_pwd "$entry"
    if [[ $from_pwd != "$entry" && $PWD == *:* ]]; then
      error "cannot resolve $entry: $PWD contains ':'; use an absolute path"
      exit 1
    fi
    resolved+=("$from_pwd")
  done
  LETS_ENV_FILES="${resolved[*]}"
}

env_flags=''

while [ "$#" -gt 0 ]; do
  case "$1" in
  -E | --env-file)
    env_file "${2:-}"
    shift 2
    ;;
  --env-file=*)
    env_file "${1#--env-file=}"
    shift
    ;;
  --no-env-files)
    export LETS_NO_ENV_FILES=1
    shift
    ;;
  *) break ;;
  esac
  env_flags=1
done

if [ "$#" -lt 1 ]; then
  usage
fi

if [ -n "${LETS_ENV_FILES:-}" ]; then
  env_files_from_pwd
fi

flake_root() {
  local dir="$PWD"
  while :; do
    if [ -e "$dir/flake.nix" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    [ "$dir" = "/" ] && return 1
    dir="${dir%/*}"
    [ -z "$dir" ] && dir="/"
  done
}

run_target() {
  local root
  if ! root="$(flake_root)"; then
    error "no flake.nix found in $PWD or any parent directory"
    exit 1
  fi
  cd "$root" || exit 1
  exec nix run --option warn-dirty false ".#$1" -- "${@:2}"
}

case "$1" in
-h | --help | -s | --show | -c | --completions | -v | --version)
  if [ -n "$env_flags" ]; then
    error "env flags apply to a task, not to $1"
    exit 1
  fi
  ;;
esac

case "$1" in
-h | --help)
  shift
  run_target help "$@"
  ;;
-s | --show)
  shift
  run_target show "$@"
  ;;
-c | --completions)
  shift
  run_target completions "$@"
  ;;
-v | --version)
  echo
  bold_cyan " lets - A Nix Task Runner"
  dim "-------------------------"
  echo
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
  case "$1" in
  -*) error "unknown option \"$1\"" ;;
  *) error "unknown task \"$1\"" ;;
  esac
  exit 1
fi

shift "$consumed"
run_target "$target" "$@"
