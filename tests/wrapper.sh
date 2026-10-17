#!/usr/bin/env bash
set -uo pipefail

lets_bin="$1"
stub="$(mktemp -d)"
cat >"$stub/nix" <<EOF
#!$BASH
printf 'sources=%s no=%s args=%s%s\n' "\${LETS_ENV_SOURCES-unset}" \
  "\${LETS_NO_ENV_FILES-unset}" "\$*" \
  "\${LETS_ENV_FILES+ files=\$LETS_ENV_FILES}"
EOF
chmod +x "$stub/nix"
PATH="$stub:$PATH"
export PATH
touch flake.nix

fail=0
assert() {
  local desc="$1" expected="$2"
  shift 2
  local got
  got="$("$lets_bin" "$@" 2>&1)"
  if [ "$got" = "$expected" ]; then
    printf '  ✅ %s\n' "$desc"
  else
    printf '  ❌ %s\n     expected: [%s]\n     got:      [%s]\n' \
      "$desc" "$expected" "$got"
    fail=1
  fi
}
run_args='run --option warn-dirty false .#demo --'

assert "no flag" "sources=unset no=unset args=$run_args" demo
assert "-E" "sources=file:$PWD/a.env no=unset args=$run_args" -E a.env demo
assert "two -E" "sources=file:$PWD/a.env
file:$PWD/b.env no=unset args=$run_args" \
  -E a.env --env-file b.env demo
assert "--env-file=" "sources=file:$PWD/a.env no=unset args=$run_args" \
  --env-file=a.env demo
assert "--no-env-files" "sources=unset no=1 args=$run_args" \
  --no-env-files demo
assert "task args pass through" \
  "sources=file:$PWD/a.env no=unset args=$run_args --locale fr" \
  -E a.env demo --locale fr
assert "absolute -E stays as is" \
  "sources=file:/abs/a.env no=unset args=$run_args" -E /abs/a.env demo
# shellcheck disable=SC2016,SC2088
assert '-E with ~ or $ is not resolved by the wrapper' \
  "sources=file:~/a.env
file:\$D/b.env no=unset args=$run_args" \
  -E '~/a.env' -E '$D/b.env' demo
# shellcheck disable=SC2016
assert '-E with an inner $ resolves from the current directory' \
  "sources=file:$PWD/cfg/\$S.env no=unset args=$run_args" -E 'cfg/$S.env' demo
# shellcheck disable=SC2016
LETS_ENV_FILES='a.env:/abs/b.env:$D/c.env' assert \
  "relative LETS_ENV_FILES resolve from the current directory" \
  "sources=unset no=unset args=$run_args \
files=$PWD/a.env:/abs/b.env:\$D/c.env" demo
LETS_ENV_FILES=':a.env::b.env:' assert "empty LETS_ENV_FILES entries" \
  "sources=unset no=unset args=$run_args files=$PWD/a.env:$PWD/b.env" demo
assert "-E without a value" "ERROR: --env-file needs a file" -E
assert "--env-file= without a value" "ERROR: --env-file needs a file" \
  --env-file= demo
assert "-E with a newline" "ERROR: --env-file value cannot span lines" \
  -E $'a\nb.env' demo
assert "-E without a task" \
  "Usage: lets [-E <file>]... [--no-env-files] <task> [args...]" -E a.env
assert "-E before --help" "ERROR: env flags apply to a task, not to --help" \
  -E a.env --help
assert "--no-env-files before -v" \
  "ERROR: env flags apply to a task, not to -v" --no-env-files -v
# shellcheck disable=SC2016
dollar_dir='dollar$dir'
mkdir "$dollar_dir"
(
  cd "$dollar_dir" || exit 1
  assert "relative -E from a directory with a dollar sign" \
    "ERROR: cannot resolve a.env: $PWD contains '\$'; use an absolute path" \
    -E a.env demo
  exit "$fail"
) || fail=1
mkdir colon:dir
(
  cd colon:dir || exit 1
  LETS_ENV_FILES=a.env assert \
    "relative LETS_ENV_FILES from a directory with a colon" \
    "ERROR: cannot resolve a.env: $PWD contains ':'; use an absolute path" demo
  LETS_ENV_FILES=/abs/a.env assert \
    "absolute LETS_ENV_FILES from a directory with a colon" \
    "sources=unset no=unset args=$run_args files=/abs/a.env" demo
  assert "relative -E from a directory with a colon" \
    "sources=file:$PWD/a.env no=unset args=$run_args" -E a.env demo
  exit "$fail"
) || fail=1
assert "unknown flag" 'ERROR: unknown option "-x"' -x demo

if [ "$fail" = 0 ]; then
  echo "✅ wrapper assertions passed"
else
  echo "❌ wrapper assertions failed" >&2
fi
exit "$fail"
