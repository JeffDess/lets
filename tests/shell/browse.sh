#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$script_dir/../../tasks/browse/browse.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
results="$test_dir/results"
: >"$results"

check() (
  local label=$1 platform=$2 wsl=$3 available=$4 opener_status=$5
  local url=$6 expected_status=$7 expected_output=$8 diagnostic=$9
  local status=0

  uname() { printf '%s\n' "$platform"; }
  grep() { [[ $wsl == true ]]; }
  open() {
    printf 'open:%s:%s\n' "$#" "$1"
    return "$opener_status"
  }
  xdg-open() {
    printf 'xdg-open:%s:%s\n' "$#" "$1"
    return "$opener_status"
  }
  wslview() {
    printf 'wslview:%s:%s\n' "$#" "$1"
    return "$opener_status"
  }
  command() { [[ $available == true ]]; }
  info() { printf 'INFO: %s\n' "$*"; }
  error() { printf 'ERROR: %s\n' "$*" >&2; }

  # Run with the strict mode used by writeShellApplication.
  set +e
  (
    set -e
    # shellcheck disable=SC1090
    source "$script"
  ) >"$test_dir/out" 2>"$test_dir/err"
  status=$?
  set -e
  local out err problem=''
  out=$(<"$test_dir/out")
  err=$(<"$test_dir/err")
  if [[ $status != "$expected_status" ]]; then
    problem="status $status, expected $expected_status"
  elif [[ $out != "$expected_output" ]]; then
    problem="stdout was: $out"
  elif [[ -n $diagnostic && $err != *"$diagnostic"* ]] ||
    [[ -z $diagnostic && -n $err ]]; then
    problem="stderr was: $err"
  fi

  # NOTE: Results go to a file because calling check in a condition would
  # disable set -e inside the sourced script.
  if [[ -z $problem ]]; then
    printf '  ✅ %s\n' "$label"
    echo pass >>"$results"
  else
    printf '  ❌ %s (%s)\n' "$label" "$problem"
    echo fail >>"$results"
  fi
)

url='https://example.com/a path?q=one&other=two'
opened="INFO: Opening $url in your browser"$'\n'
install='INFO: Please install wslview: https://wslutiliti.es/wslu/install.html'
check macOS Darwin false true 0 "$url" 0 "${opened}open:1:$url" ''
check Linux Linux false true 0 "$url" 0 "${opened}xdg-open:1:$url" ''
check 'macOS opener failure' Darwin false true 7 "$url" 7 \
  "${opened}open:1:$url" ''
check 'Linux opener failure' Linux false true 7 "$url" 7 \
  "${opened}xdg-open:1:$url" ''

if [[ -r /proc/version ]]; then
  check WSL Linux true true 0 "$url" 0 "${opened}wslview:1:$url" ''
  check 'WSL opener failure' Linux true true 7 "$url" 7 \
    "${opened}wslview:1:$url" ''
  check 'missing wslview' Linux true false 0 "$url" 1 \
    "${opened}${install}" "ERROR: Unable to open: $url"
else
  printf '  ⏭️ WSL checks (skipped: require /proc/version)\n'
fi

mapfile -t outcomes <"$results"
total=${#outcomes[@]}
failed=0
for outcome in "${outcomes[@]}"; do
  [[ $outcome == pass ]] || failed=$((failed + 1))
done

if [[ $failed -eq 0 ]]; then
  echo "✅ ${total}/${total} passed"
else
  echo "❌ ${failed}/${total} failed"
  exit 1
fi
