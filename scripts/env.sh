#!/usr/bin/env bash

_LETS_ENV_NAME='[A-Za-z_][A-Za-z0-9_]*'

_lets_env_snapshot() {
  [ -z "${_lets_env_snapped:-}" ] || return 0
  _lets_env_snapped=1
  local - IFS=$'\n' _lets_line _lets_name _lets_flags='[A-Za-z_-]*'
  local _lets_re="^(declare -${_lets_flags}x${_lets_flags}|export) "
  _lets_re+="($_LETS_ENV_NAME)"
  set -f +x
  for _lets_line in $(export -p); do
    if [[ $_lets_line =~ $_lets_re ]]; then
      _lets_name="${BASH_REMATCH[2]}"
      if [ -n "${!_lets_name+x}" ]; then
        _LETS_ENV["$_lets_name"]="${!_lets_name}"
      fi
    fi
  done
  for _lets_line in $(declare -p); do
    if [[ $_lets_line =~ ^declare\ -([A-Za-z-]+)\ ($_LETS_ENV_NAME) ]] &&
      [ -n "${BASH_REMATCH[1]//[x-]/}" ]; then
      _LETS_ENV_RESERVED+=("${BASH_REMATCH[2]}")
    fi
  done
}

_lets_env_quiet() {
  [ "${_lets_mode:-}" = auto ] && [ "$_LETS_SECRET_ON_ERROR" = ignore ]
}

_lets_env_fail() {
  if [ "$_lets_tag" = secrets ] && _lets_env_lenient "$1"; then
    return 0
  fi
  error "$_lets_tag: $1$_lets_env_from"
  return 1
}

_lets_env_eval() {
  local _lets_text="$1" _lets_label="$2" _lets_override="$3" _lets_k _lets_v
  local _lets_hint='' _lets_skip _lets_filled=''
  local -a _lets_keys=() _lets_skipped=() _lets_empty=()
  local -A _lets_new=() _lets_probe=()
  _lets_env_snapshot
  if [ "$_lets_tag" = secrets ]; then
    _lets_hint=', decoder output must be KEY=VALUE lines'
  fi
  for _lets_k in "${!_LETS_SCOPE[@]}"; do
    _lets_new["$_lets_k"]="${_LETS_SCOPE[$_lets_k]}"
  done
  if ! dotenv_eval_string "$_lets_text" "$_lets_override" _LETS_ENV \
    _lets_new _lets_keys _LETS_ENV_RESERVED _lets_probe _LETS_ENV_FIXED; then
    [ "$DOTENV_ERROR_KIND" = parse ] || _lets_hint=''
    _lets_env_fail "$_lets_label:$DOTENV_ERROR$_lets_hint"
    return
  fi
  _lets_skipped=("${DOTENV_SKIPPED[@]}")
  if ! _lets_env_quiet; then
    for _lets_skip in "${_lets_skipped[@]}"; do
      warn "$_lets_tag: $_lets_label:${_lets_skip%%:*}: ${_lets_skip#*:} is \
reserved, skipped$_lets_env_from"
    done
  fi
  if [ "$_lets_tag" = secrets ]; then
    for _lets_k in "${_lets_keys[@]}"; do
      if [ -n "${_lets_probe[$_lets_k]+x}" ]; then
        _lets_v="${_lets_probe[$_lets_k]}"
      else
        _lets_v="${_lets_new[$_lets_k]}"
      fi
      if [ -n "$_lets_v" ]; then
        _lets_filled=1
      else
        _lets_empty+=("$_lets_k")
      fi
      if [[ $_lets_v =~ ^=+$ ]]; then
        _lets_env_fail "$_lets_label: a value is only '='$_lets_hint"
        return
      fi
    done
    if [ -z "$_lets_filled" ]; then
      _lets_env_fail "$_lets_label printed no KEY=VALUE line with a value"
      return
    fi
  fi
  for _lets_k in "${!_lets_new[@]}"; do
    _LETS_SCOPE["$_lets_k"]="${_lets_new[$_lets_k]}"
  done
  if ! _lets_env_quiet; then
    for _lets_k in "${_lets_empty[@]}"; do
      warn "secrets: $_lets_label: $_lets_k is empty$_lets_env_from"
    done
  fi
}

_lets_env_absent() {
  local _lets_dir="$1"
  while [[ $_lets_dir == */* ]]; do
    _lets_dir="${_lets_dir%/*}"
    _lets_dir="${_lets_dir:-/}"
    if [ -d "$_lets_dir" ]; then
      [ -x "$_lets_dir" ]
      return
    fi
  done
  return 0
}

_lets_env_load() {
  local _lets_text _lets_tag=env
  if [ -L "$1" ] && [ ! -e "$1" ]; then
    error "env: $1 is a broken symlink$_lets_env_from"
    return 1
  fi
  if [ ! -e "$1" ] && _lets_env_absent "$1"; then
    if [ "$2" = 1 ]; then
      error "env: $1 not found$_lets_env_from"
      return 1
    fi
    warn "env: $1 not found, skipped$_lets_env_from"
    return 0
  fi
  if [ ! -e "$1" ] || [ -d "$1" ] || [ ! -r "$1" ]; then
    error "env: $1 is not a readable file$_lets_env_from"
    return 1
  fi
  _dotenv_read "$1" _lets_text || {
    if [ "$?" = 2 ]; then
      error "env: $1 contains NUL bytes$_lets_env_from"
    else
      error "env: cannot read $1$_lets_env_from"
    fi
    return 1
  }
  _lets_env_eval "$_lets_text" "$1" "$2"
}

_lets_env_expand() {
  local _lets_rest="$1" _lets_name _lets_value
  local _lets_braced="^\{($_LETS_ENV_NAME)\}(.*)$"
  local _lets_bare="^($_LETS_ENV_NAME)(.*)$"
  _lets_env_path=''
  if [[ $_lets_rest == \~/* ]]; then
    _lets_rest="\${HOME}${_lets_rest#\~}"
  fi
  while [[ $_lets_rest == *'$'* ]]; do
    _lets_env_path+="${_lets_rest%%\$*}"
    _lets_rest="${_lets_rest#*\$}"
    if [[ $_lets_rest =~ $_lets_braced || $_lets_rest =~ $_lets_bare ]]; then
      _lets_name="${BASH_REMATCH[1]}"
      _lets_rest="${BASH_REMATCH[2]}"
      if [ -n "${_LETS_SCOPE[$_lets_name]+x}" ]; then
        _lets_value="${_LETS_SCOPE[$_lets_name]}"
      elif [ -n "${!_lets_name+x}" ]; then
        _lets_value="${!_lets_name}"
      else
        _lets_env_missing="$_lets_name is not set"
        return 1
      fi
      if [ -z "$_lets_value" ]; then
        _lets_env_missing="$_lets_name is empty"
        return 1
      fi
      _lets_env_path+="$_lets_value"
    else
      _lets_env_missing=''
      return 1
    fi
  done
  _lets_env_path+="$_lets_rest"
}

_lets_env_reinstantiate() {
  local _lets_root="$PWD"
  while [ ! -e "$_lets_root/flake.nix" ]; do
    [ -n "$_lets_root" ] || return 0
    _lets_root="${_lets_root%/*}"
  done
  warn "secrets: re-evaluating ${_lets_root:-/} to rebuild the decoder"
  (cd -- "${_lets_root:-/}" &&
    nix path-info --derivation --no-eval-cache ".#$_LETS_TASK_KEY") \
    </dev/null >/dev/null 2>&1 || :
}

_lets_env_secret() {
  local - _lets_name="$1" _lets_override="$2" _lets_mode="$3" _lets_arg
  local _lets_out _lets_status=0 _lets_env_from="${4:+ (from $4)}" _lets_dir=.
  local _lets_tag=secrets _lets_k
  set +x
  if [ -z "$_LETS_SECRET_BIN" ]; then
    error "secrets: no decoder configured (secrets.command)$_lets_env_from"
    return 1
  fi
  if [ ! -x "$_LETS_SECRET_BIN" ]; then
    [ -z "$_LETS_SECRET_DRV" ] || [ -e "$_LETS_SECRET_DRV" ] ||
      _lets_env_reinstantiate
    if [ -z "$_LETS_SECRET_DRV" ] ||
      ! nix-store --realise --no-gc-warning "$_LETS_SECRET_DRV" >/dev/null; then
      error "secrets: cannot build the decoder$_lets_env_from; run the task \
with nix run --no-eval-cache, through lets or in the dev shell"
      return 1
    fi
  fi
  if [ "$_lets_mode" = cli ]; then
    _lets_dir="${LETS_SECRETS_DIR:-$PWD}"
    if [ ! -d "$_lets_dir" ]; then
      error "secrets: LETS_SECRETS_DIR $_lets_dir is not a \
directory$_lets_env_from"
      return 1
    fi
  fi
  _lets_arg="${_LETS_SECRET_PATTERN/\{name\}/"$_lets_name"}"
  _lets_out="$(
    for _lets_k in "${!_LETS_SCOPE[@]}"; do
      export -- "$_lets_k=${_LETS_SCOPE[$_lets_k]}"
    done
    if _lets_env_quiet; then
      exec 2>/dev/null
    fi
    cd -- "$_lets_dir" && "$_LETS_SECRET_BIN" "$_lets_arg"
    _lets_status=$?
    printf .
    exit "$_lets_status"
  )" || _lets_status=$?
  _lets_out="${_lets_out%.}"
  if [ "$_lets_status" -eq 126 ] || [ "$_lets_status" -eq 127 ]; then
    error "secrets: $_lets_arg: decoder command not found or not executable \
(exit $_lets_status)$_lets_env_from; check secrets.command and \
secrets.runtimeInputs"
    return 1
  fi
  if [ "$_lets_status" -ne 0 ]; then
    _lets_env_fail "$_lets_arg failed (exit $_lets_status)"
    return
  fi
  if [[ $_lets_out != *[![:space:]]* ]]; then
    _lets_env_fail "$_lets_arg printed nothing"
    return
  fi
  _lets_env_eval "$_lets_out" "$_lets_arg" "$_lets_override"
}

_lets_env_lenient() {
  [ "$_lets_mode" = auto ] || return 1
  case "$_LETS_SECRET_ON_ERROR" in
  warn)
    warn "secrets: $1, skipped$_lets_env_from"
    return 0
    ;;
  ignore) return 0 ;;
  esac
  return 1
}

_lets_env_cli_file() {
  local _lets_env_from=" (from $2)"
  if ! _lets_env_expand "$1"; then
    if [ -n "$_lets_env_missing" ]; then
      error "env: $1: $_lets_env_missing$_lets_env_from"
    else
      error "env: $1: only \$VAR and \${VAR} are expanded$_lets_env_from"
    fi
    return 1
  fi
  _lets_env_load "$_lets_env_path" 1
}

_lets_env_vars() {
  local - _lets_line _lets_key _lets_n=0
  set +x
  [ -n "${LETS_ENV_VARS:-}" ] || return 0
  _lets_env_snapshot
  while IFS= read -r _lets_line; do
    _lets_n=$((_lets_n + 1))
    [ -n "$_lets_line" ] || continue
    if [[ $_lets_line != *=* ]]; then
      error "env: LETS_ENV_VARS:$_lets_n: missing '='"
      return 1
    fi
    _lets_key="${_lets_line%%=*}"
    if [[ ! $_lets_key =~ ^$_LETS_ENV_NAME$ ]]; then
      error "env: LETS_ENV_VARS:$_lets_n: invalid variable name"
      return 1
    fi
    if _dotenv_match "$_lets_key" "${_LETS_ENV_RESERVED[@]}"; then
      error "env: $_lets_key is reserved (from -e or LETS_ENV_VARS)"
      return 1
    fi
    _LETS_ENV_FIXED["$_lets_key"]="${_lets_line#*=}"
  done < <(printf '%s\n' "$LETS_ENV_VARS")
  for _lets_key in "${!_LETS_ENV_FIXED[@]}"; do
    _LETS_ENV["$_lets_key"]="${_LETS_ENV_FIXED[$_lets_key]}"
    _LETS_SCOPE["$_lets_key"]="${_LETS_ENV_FIXED[$_lets_key]}"
  done
}

_lets_env_no_files_check() {
  case "${LETS_NO_ENV_FILES:-}" in
  '' | 1) ;;
  *) warn "env: LETS_NO_ENV_FILES must be 1 to skip env files, ignored" ;;
  esac
}

# shellcheck disable=SC2120
_lets_env_files() {
  local - _lets_entry _lets_env_from=' (from envFiles)'
  set -f +x
  [ "${LETS_NO_ENV_FILES:-}" != 1 ] || return 0
  for _lets_entry in "$@"; do
    if _lets_env_expand "$_lets_entry"; then
      _lets_env_load "$_lets_env_path" 0 || return 1
    else
      warn "env: $_lets_entry: $_lets_env_missing, skipped$_lets_env_from"
    fi
  done
}

_lets_env_secret_files() {
  local _lets_entry
  [ "${LETS_NO_ENV_FILES:-}" != 1 ] || return 0
  for _lets_entry in "${_LETS_SECRET_FILES[@]}"; do
    _lets_env_secret "$_lets_entry" 0 auto secrets.files || return 1
  done
}

# shellcheck disable=SC2120
_lets_env_task_secrets() {
  local _lets_entry
  for _lets_entry in "$@"; do
    _lets_env_secret "$_lets_entry" 0 explicit secrets || return 1
  done
}

_lets_env_cli() {
  local - IFS=: _lets_entry
  set -f +x
  for _lets_entry in ${LETS_ENV_FILES:-}; do
    [ -n "$_lets_entry" ] || continue
    _lets_env_cli_file "$_lets_entry" LETS_ENV_FILES || return 1
  done
  for _lets_entry in ${LETS_SECRETS:-}; do
    [ -n "$_lets_entry" ] || continue
    _lets_env_secret "$_lets_entry" 1 cli LETS_SECRETS || return 1
  done
  IFS=$'\n'
  for _lets_entry in ${LETS_ENV_SOURCES:-}; do
    case "$_lets_entry" in
    file:*) _lets_env_cli_file "${_lets_entry#file:}" --env-file || return 1 ;;
    secret:*)
      _lets_env_secret "${_lets_entry#secret:}" 1 cli --secret || return 1
      ;;
    *)
      error "env: bad LETS_ENV_SOURCES entry '$_lets_entry'"
      return 1
      ;;
    esac
  done
}

_lets_env_export() {
  local - _lets_k
  set +x
  for _lets_k in "${!_LETS_ENV_FIXED[@]}"; do
    _LETS_SCOPE["$_lets_k"]="${_LETS_ENV_FIXED[$_lets_k]}"
  done
  for _lets_k in "${!_LETS_SCOPE[@]}"; do
    export -- "$_lets_k=${_LETS_SCOPE[$_lets_k]}"
  done
  unset LETS_ENV_FILES LETS_SECRETS LETS_ENV_SOURCES LETS_ENV_VARS \
    LETS_SECRETS_DIR
}

declare -A _LETS_ENV=() _LETS_SCOPE=() _LETS_ENV_FIXED=()
