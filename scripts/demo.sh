#!/usr/bin/env bash

set -euo pipefail

locale="en_US"

while [ "$#" -gt 0 ]; do
  case "$1" in
  -l | --locale)
    if [ "$#" -lt 2 ]; then
      echo "Missing value for $1" >&2
      exit 1
    fi
    locale="$2"
    shift 2
    ;;
  --locale=*)
    locale="${1#*=}"
    shift
    ;;
  -h | --help)
    echo "Usage: test [--locale <locale> | --locale=<locale> | -l <locale>]"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 1
    ;;
  esac
done

if [[ "$locale" == *.UTF-8 ]]; then
  export LC_ALL="$locale"
else
  export LC_ALL="${locale}.UTF-8"
fi

assert_hello_output() {
  local label="$1"
  shift
  local output

  output="$("$@")"
  if [[ ! $output =~ [Hh]ello ]]; then
    echo "❌ Expected hello output in $label, got: $output" >&2
  else
    echo "✅ $label ok: $output"
  fi
}

echo "Running tests..."
assert_hello_output bash bash -lc "hello"
assert_hello_output zsh zsh -lc "hello"
assert_hello_output nushell nu -c "hello"
