#!/usr/bin/env bash

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

rebuilt=""
if [ "${1:-}" = "__rebuilt" ]; then
  rebuilt=1
  shift
fi

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
    -*)
      [ "$path" = lets ] || break
      key="${path}##${tok}"
      [ -z "${_LETS_OPTNEEDS[$key]+x}" ] || __i=$((__i + 1))
      ;;
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
  --env-file=* | --env=* | --secret=*)
    inline="${cur%%=*}="
    prev="${cur%%=*}"
    cur="${cur#*=}"
    ;;
  esac

  if [ "$path" = lets ]; then
    case "$prev" in
    -e | --env) exit 0 ;;
    -S | --secret)
      pre="${SECRETS_PATTERN%%\{name\}*}"
      suf="${SECRETS_PATTERN#*\{name\}}"
      if [ -n "$pre$suf" ]; then
        root="$(flake_root)" || root="$PWD"
        shopt -s nullglob dotglob
        for f in "$root/$pre$cur"*"$suf"; do
          f="${f#"$root/$pre"}"
          printf '%s%s\n' "$inline" "${f%"$suf"}"
        done
      fi
      exit 0
      ;;
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

one_line() {
  case "$2" in
  '')
    error "$1 needs $3"
    exit 1
    ;;
  *$'\n'*)
    error "$1 value cannot span lines"
    exit 1
    ;;
  esac
}

env_file() {
  one_line --env-file "${1:-}" "a file"
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

env_var() {
  one_line --env "${1:-}" "KEY=VALUE with a valid name"
  if [[ ! $1 =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
    error "--env needs KEY=VALUE with a valid name"
    exit 1
  fi
  export LETS_ENV_VARS="${LETS_ENV_VARS:+$LETS_ENV_VARS$'\n'}$1"
}

secret_name() {
  one_line --secret "${1:-}" "a name"
  env_source "secret:$1"
}

env_flags=''

while [ "$#" -gt 0 ]; do
  case "$1" in
  --env-file=* | --env=* | --secret=*)
    set -- "${1%%=*}" "${1#*=}" "${@:2}"
    continue
    ;;
  -E | --env-file)
    env_file "${2:-}"
    shift 2
    ;;
  -e | --env)
    env_var "${2:-}"
    shift 2
    ;;
  -S | --secret)
    secret_name "${2:-}"
    shift 2
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
  echo -n "Usage: lets [-E <file>|-S <name>|-e KEY=VALUE]..." >&2
  echo " [--no-env-files] <task> [args...]" >&2
  exit 1
fi

if [ -n "${LETS_ENV_FILES:-}" ]; then
  env_files_from_pwd
fi

run_target() {
  local root
  if ! root="$(flake_root)"; then
    error "no flake.nix found in $PWD or any parent directory"
    exit 1
  fi
  cd "$root" || exit 1
  export LETS_SECRETS_DIR="$root"
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
  *)
    if [ -z "$rebuilt" ] && root="$(flake_root)" &&
      fresh="$(nix build --option warn-dirty false --no-link \
        --print-out-paths "$root#lets")"; then
      exec "$fresh/bin/lets" __rebuilt "$@"
    fi
    error "unknown task \"$1\""
    ;;
  esac
  exit 1
fi

shift "$consumed"
run_target "${ALIASES[$target]:-$target}" "$@"
