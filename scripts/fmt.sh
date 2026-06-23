#!/usr/bin/env bash
# Text formatting helpers injected into every lets task by mkTask.

_lets_color=''
if [ -z "${NO_COLOR:-}" ] && { [ -n "${FORCE_COLOR:-}" ] || [ -t 1 ]; }; then
  _lets_color=1
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
