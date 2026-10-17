#!/usr/bin/env bash

_LETS_ENV_LETTERS='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_'
_LETS_ENV_NAME="[$_LETS_ENV_LETTERS][${_LETS_ENV_LETTERS}0123456789]*"
_LETS_ENV_SPACE=$' \t\n\v\f\r'

_lets_env_snapshot() {
  local - IFS=$'\n' _lets_line _lets_name _lets_flags="[${_LETS_ENV_LETTERS}-]*"
  local _lets_re="^(declare -${_lets_flags}x${_lets_flags}|export) "
  _lets_re+="($_LETS_ENV_NAME)"
  set -f +x
  for _lets_line in $(export -p); do
    if [[ $_lets_line =~ $_lets_re ]]; then
      _lets_name="${BASH_REMATCH[2]}"
      if [ -n "${!_lets_name+x}" ]; then
        _LETS_CALLER_ENV["$_lets_name"]="${!_lets_name}"
      fi
    fi
  done
}

_lets_env_protected() {
  local _lets_decl
  case "$1" in
  _lets_* | _LETS_* | BASH_*) return 0 ;;
  esac
  if [ -n "${_LETS_ENV_PROTECTED[$1]+x}" ]; then
    return 0
  fi
  _lets_decl="$(declare -p "$1" 2>/dev/null)" || return 1
  _lets_decl="${_lets_decl#declare -}"
  _lets_decl="${_lets_decl%% *}"
  [ -n "${_lets_decl//[x-]/}" ]
}

_lets_env_kept() {
  if [ -n "${_LETS_ENV_PINNED[$1]+x}" ] && [ "$3" != cli ]; then
    return 0
  fi
  [ -z "$2" ] || return 1
  [ -n "${_LETS_CALLER_ENV[$1]+x}" ] || return 1
  [ -n "${!1+x}" ] || return 1
  [ "${!1}" = "${_LETS_CALLER_ENV[$1]}" ] || return 1
  [ "$3" = auto ] || [ -z "${_LETS_ENV_MATCHED[$1]+x}" ]
}

_lets_env_match() {
  if [ -z "${_LETS_CALLER_ENV[$1]+x}" ]; then
    return 0
  fi
  if [ -n "${!1+x}" ] && [ "${!1}" = "$2" ]; then
    _LETS_ENV_MATCHED["$1"]=1
  else
    unset "_LETS_ENV_MATCHED[$1]"
  fi
}

_lets_env_trim() {
  _lets_trim="${1#"${1%%[!"$_LETS_ENV_SPACE"]*}"}"
  _lets_trim="${_lets_trim%"${_lets_trim##*[!"$_LETS_ENV_SPACE"]}"}"
}

_lets_env_file() {
  local IFS= _lets_file="$1" _lets_override="$2" _lets_mode="$3" _lets_n=0
  local _lets_label="${4:-$1}" _lets_line _lets_key _lets_value _lets_i
  local -a _lets_keys=() _lets_values=()
  while read -r _lets_line || [ -n "$_lets_line" ]; do
    _lets_n=$((_lets_n + 1))
    if [ "$_lets_n" = 1 ]; then
      _lets_line="${_lets_line#$'\xef\xbb\xbf'}"
    fi
    _lets_env_trim "${_lets_line%$'\r'}"
    _lets_line="$_lets_trim"
    case "$_lets_line" in
    '' | '#'*) continue ;;
    esac
    if [[ $_lets_line == export["$_LETS_ENV_SPACE"]* ]]; then
      _lets_env_trim "${_lets_line#export}"
      _lets_line="$_lets_trim"
    fi
    if [[ $_lets_line != *=* ]]; then
      error "load_env: $_lets_label:$_lets_n: missing '='$_lets_env_from"
      return 1
    fi
    _lets_env_trim "${_lets_line%%=*}"
    _lets_key="$_lets_trim"
    if [[ ! $_lets_key =~ ^$_LETS_ENV_NAME$ ]]; then
      error "load_env: $_lets_label:$_lets_n: invalid variable name \
'$_lets_key'$_lets_env_from"
      return 1
    fi
    _lets_env_trim "${_lets_line#*=}"
    _lets_value="$_lets_trim"
    if [[ $_lets_value == [\"\']* ]]; then
      if [ "${#_lets_value}" -lt 2 ] ||
        [ "${_lets_value: -1}" != "${_lets_value:0:1}" ]; then
        if [[ ${_lets_value:1} == *"${_lets_value:0:1}"* ]]; then
          error "load_env: $_lets_label:$_lets_n: text after the closing \
quote, inline comments are not supported$_lets_env_from"
        else
          error "load_env: $_lets_label:$_lets_n: unmatched \
quote$_lets_env_from"
        fi
        return 1
      fi
      _lets_value="${_lets_value:1:${#_lets_value}-2}"
    fi
    if _lets_env_protected "$_lets_key"; then
      warn "load_env: $_lets_label:$_lets_n: $_lets_key is reserved, \
skipped$_lets_env_from"
      continue
    fi
    _lets_keys+=("$_lets_key")
    _lets_values+=("$_lets_value")
  done <"$_lets_file" || {
    error "load_env: cannot read $_lets_label$_lets_env_from"
    return 1
  }
  for _lets_i in "${!_lets_keys[@]}"; do
    _lets_key="${_lets_keys[_lets_i]}"
    _lets_value="${_lets_values[_lets_i]}"
    if [ "$_lets_mode" = auto ]; then
      _lets_env_match "$_lets_key" "$_lets_value"
    fi
    if _lets_env_kept "$_lets_key" "$_lets_override" "$_lets_mode"; then
      continue
    fi
    export -- "$_lets_key=$_lets_value"
    if [ "$_lets_mode" = cli ]; then
      _LETS_ENV_PINNED["$_lets_key"]=1
    fi
  done
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
  if [ -L "$1" ] && [ ! -e "$1" ]; then
    error "load_env: $1 is a broken symlink$_lets_env_from"
    return 1
  fi
  if [ ! -e "$1" ] && _lets_env_absent "$1"; then
    if [ "$3" != auto ]; then
      error "load_env: $1 not found$_lets_env_from"
      return 1
    fi
    warn "load_env: $1 not found, skipped$_lets_env_from"
    return 0
  fi
  if [ ! -e "$1" ] || [ -d "$1" ] || [ ! -r "$1" ]; then
    error "load_env: $1 is not a readable file$_lets_env_from"
    return 1
  fi
  _lets_env_file "$@"
}

_lets_env_expand() {
  local _lets_rest="$1" _lets_name
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
      if [ -z "${!_lets_name+x}" ]; then
        _lets_env_missing="$_lets_name is not set"
        return 1
      fi
      if [ -z "${!_lets_name}" ]; then
        _lets_env_missing="$_lets_name is empty"
        return 1
      fi
      _lets_env_path+="${!_lets_name}"
      _lets_rest="${BASH_REMATCH[2]}"
    else
      _lets_env_missing=''
      return 1
    fi
  done
  _lets_env_path+="$_lets_rest"
}

_lets_env_cli_file() {
  local _lets_env_from=" (from $2)"
  if ! _lets_env_expand "$1"; then
    if [ -n "$_lets_env_missing" ]; then
      error "load_env: $1: $_lets_env_missing$_lets_env_from"
    else
      error "load_env: $1: only \$VAR and \${VAR} are expanded$_lets_env_from"
    fi
    return 1
  fi
  _lets_env_load "$_lets_env_path" 1 cli
}

_lets_env_anchor() {
  local _lets_entry _lets_anchored=()
  for _lets_entry in ${LETS_ENV_FILES:-}; do
    [ -n "$_lets_entry" ] || continue
    case "$_lets_entry" in
    /* | \~/* | '$'*) ;;
    *)
      if [[ $PWD == *['$:']* ]]; then
        error "load_env: cannot resolve $_lets_entry: $PWD contains '\$' or \
':' (from LETS_ENV_FILES)"
        return 1
      fi
      _lets_entry="$PWD/$_lets_entry"
      ;;
    esac
    _lets_anchored+=("$_lets_entry")
  done
  LETS_ENV_FILES="${_lets_anchored[*]}"
}

_lets_env_vars() {
  local _lets_line _lets_key _lets_n=0
  [ -n "${LETS_ENV_VARS:-}" ] || return 0
  while IFS= read -r _lets_line; do
    _lets_n=$((_lets_n + 1))
    [ -n "$_lets_line" ] || continue
    if [[ $_lets_line != *=* ]]; then
      error "load_env: LETS_ENV_VARS:$_lets_n: missing '='"
      return 1
    fi
    _lets_key="${_lets_line%%=*}"
    if [[ ! $_lets_key =~ ^$_LETS_ENV_NAME$ ]]; then
      error "load_env: LETS_ENV_VARS:$_lets_n: invalid variable name"
      return 1
    fi
    if _lets_env_protected "$_lets_key"; then
      error "load_env: $_lets_key is reserved (from -e or LETS_ENV_VARS)"
      return 1
    fi
    export -- "$_lets_key=${_lets_line#*=}"
    _LETS_ENV_PINNED["$_lets_key"]=1
  done <<<"$LETS_ENV_VARS"
}

# shellcheck disable=SC2120
_lets_env_autoload() {
  local - IFS=: _lets_entry _lets_env_from=' (from envFiles)'
  set -f +x
  if [ -z "${LETS_NO_ENV_FILES:-}" ]; then
    for _lets_entry in "$@"; do
      if _lets_env_expand "$_lets_entry"; then
        _lets_env_load "$_lets_env_path" '' auto || return 1
      else
        warn "load_env: $_lets_entry: $_lets_env_missing, \
skipped$_lets_env_from"
      fi
    done
  fi
  if [ -n "${LETS_ENV_FILES:-}" ]; then
    _lets_env_anchor || return 1
  fi
  for _lets_entry in ${LETS_ENV_FILES:-}; do
    _lets_env_cli_file "$_lets_entry" LETS_ENV_FILES || return 1
  done
  IFS=$'\n'
  for _lets_entry in ${LETS_ENV_SOURCES:-}; do
    case "$_lets_entry" in
    file:*) _lets_env_cli_file "${_lets_entry#file:}" --env-file || return 1 ;;
    *)
      error "load_env: bad LETS_ENV_SOURCES entry '$_lets_entry'"
      return 1
      ;;
    esac
  done
  _lets_env_vars || return 1
}

load_env() {
  local - _lets_override='' _lets_file
  set +x
  local _lets_usage='usage: load_env [-o|--override] [--] FILE...'
  while [ "$#" -gt 0 ]; do
    case "$1" in
    -o | --override)
      _lets_override=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      error "load_env: unknown option '$1'"
      error "$_lets_usage"
      return 1
      ;;
    *) break ;;
    esac
  done
  if [ "$#" -eq 0 ]; then
    error "$_lets_usage"
    return 1
  fi
  for _lets_file in "$@"; do
    _lets_env_load "$_lets_file" "$_lets_override" explicit || return 1
  done
}

declare -A _LETS_CALLER_ENV=() _LETS_ENV_MATCHED=() _LETS_ENV_PINNED=()
_lets_env_missing='' _lets_env_from=''
_lets_env_snapshot
