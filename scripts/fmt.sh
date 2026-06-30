#!/usr/bin/env bash
# Text formatting helpers injected into every lets task by mkTask.

_lets_color=''
if [ -z "${NO_COLOR:-}" ] && { [ -n "${FORCE_COLOR:-}" ] || [ -t 1 ]; }; then
  _lets_color=1
fi

# shellcheck disable=SC2034
_lets_color_err=''
if [ -z "${NO_COLOR:-}" ] && { [ -n "${FORCE_COLOR:-}" ] || [ -t 2 ]; }; then
  _lets_color_err=1
fi

_lets_sgr() {
  if [ -n "$_lets_color" ]; then printf '\033[%sm' "$1"; fi
}

_lets_emit() {
  local codes="$1"
  shift
  if [ -n "$_lets_color" ]; then
    printf '\033[%sm%s\033[0m\n' "$codes" "$*"
  else
    printf '%s\n' "$*"
  fi
}

_lets_logline() {
  local on="$1" code="$2" level="$3"
  shift 3
  if [ -n "$on" ]; then
    printf '\033[%sm%s\033[0m: %s\n' "$code" "$level" "$*"
  else
    printf '%s: %s\n' "$level" "$*"
  fi
}
