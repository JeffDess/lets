#!/usr/bin/env bash
# shellcheck disable=SC2154

# NOTE: `$locale` and `$name` are provided by mkTask's argument-parsing
echo "Hello, $name!"

if [[ $locale == *.UTF-8 ]]; then
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
