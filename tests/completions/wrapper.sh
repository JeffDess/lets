#!/usr/bin/env bash
set -uo pipefail

lets_bin="$1"
stub="$(mktemp -d)"
cat >"$stub/nix" <<EOF
#!$BASH
if [ "\$1" = build ]; then
  printf '%s\n' "\$*" >>"$stub/builds"
  [ -n "\${STUB_BUILT:-}" ] || { echo "stub: build failed" >&2; exit 1; }
  printf '%s\n' "\$STUB_BUILT"
  exit 0
fi
printf 'sources=%s no=%s vars=%s args=%s%s\n' \
  "\${LETS_ENV_SOURCES-unset}" "\${LETS_NO_ENV_FILES-unset}" \
  "\${LETS_ENV_VARS-unset}" "\$*" \
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

base="sources=unset no=unset vars=unset"
assert "no flag" "$base args=$run_args" demo
assert "alias runs its task" "$base args=$run_args" greet
assert "multi-word alias runs its task" \
  "$base args=run --option warn-dirty false .#lint_nix -- --fix" nix lint --fix
assert "-E" "sources=file:$PWD/a.env no=unset vars=unset args=$run_args" \
  -E a.env demo
assert "two -E" \
  "sources=file:$PWD/a.env
file:$PWD/b.env no=unset vars=unset args=$run_args" \
  -E a.env --env-file b.env demo
assert "--env-file=" \
  "sources=file:$PWD/a.env no=unset vars=unset args=$run_args" \
  --env-file=a.env demo
assert "--no-env-files" \
  "sources=unset no=1 vars=unset args=$run_args" \
  --no-env-files demo
assert "task args pass through" \
  "sources=file:$PWD/a.env no=unset vars=unset args=$run_args --locale fr" \
  -E a.env demo --locale fr
assert "-e" "sources=unset no=unset vars=A=1 args=$run_args" \
  -e A=1 demo
assert "env flags after the task go to the task" \
  "$base args=$run_args -E a.env -e A=1 -S dev --no-env-files" \
  demo -E a.env -e A=1 -S dev --no-env-files
assert "two -e" "sources=unset no=unset vars=A=1
B=x=y args=$run_args" -e A=1 --env B=x=y demo
assert "--env=" \
  "sources=unset no=unset vars=A=1 args=$run_args" \
  --env=A=1 demo
assert "-e without =" \
  'ERROR: --env needs KEY=VALUE with a valid name' -e A demo
assert "-e without a value" \
  'ERROR: --env needs KEY=VALUE with a valid name' -e
assert "-S" "sources=secret:dev no=unset vars=unset args=$run_args" \
  -S dev demo
assert "two -S" \
  "sources=secret:dev
secret:ci no=unset vars=unset args=$run_args" \
  -S dev --secret ci demo
assert "--secret=" \
  "sources=secret:dev no=unset vars=unset args=$run_args" \
  --secret=dev demo
assert "-S without a value" "ERROR: --secret needs a name" -S
assert "-S with a newline" "ERROR: --secret value cannot span lines" \
  -S $'dev\nci' demo
assert "-S before -c" "ERROR: env flags apply to a task, not to -c" \
  -S dev -c
assert "-E then -S keep flag order" \
  "sources=file:$PWD/a.env
secret:dev no=unset vars=unset args=$run_args" \
  -E a.env -S dev demo
assert "absolute -E stays as is" \
  "sources=file:/abs/a.env no=unset vars=unset args=$run_args" \
  -E /abs/a.env demo
# shellcheck disable=SC2016,SC2088
assert '-E with ~ or $ is not resolved by the wrapper' \
  "sources=file:~/a.env
file:\$D/b.env no=unset vars=unset args=$run_args" \
  -E '~/a.env' -E '$D/b.env' demo
# shellcheck disable=SC2016
assert '-E with an inner $ resolves from the current directory' \
  "sources=file:$PWD/cfg/\$S.env no=unset vars=unset args=$run_args" \
  -E 'cfg/$S.env' demo
# shellcheck disable=SC2016
LETS_ENV_FILES='a.env:/abs/b.env:$D/c.env' assert \
  "relative LETS_ENV_FILES resolve from the current directory" \
  "sources=unset no=unset vars=unset args=$run_args \
files=$PWD/a.env:/abs/b.env:\$D/c.env" demo
LETS_ENV_FILES=':a.env::b.env:' assert "empty LETS_ENV_FILES entries" \
  "sources=unset no=unset vars=unset args=$run_args \
files=$PWD/a.env:$PWD/b.env" demo
touch g1.env
LETS_ENV_FILES='g*.env' assert "LETS_ENV_FILES entries are not globbed" \
  "sources=unset no=unset vars=unset args=$run_args files=$PWD/g*.env" demo
assert "-e rejects a newline" 'ERROR: --env value cannot span lines' \
  -e $'A=1\nB=2' demo
assert "-e rejects an invalid name" \
  'ERROR: --env needs KEY=VALUE with a valid name' \
  -e 1BAD=x demo
assert "-E without a value" "ERROR: --env-file needs a file" -E
assert "--env-file= without a value" "ERROR: --env-file needs a file" \
  --env-file= demo
assert "--secret= without a value" "ERROR: --secret needs a name" \
  --secret= demo
assert "--env= without a value" \
  'ERROR: --env needs KEY=VALUE with a valid name' --env= demo
assert "--env-file= keeps the rest after the first =" \
  "sources=file:$PWD/=a.env no=unset vars=unset args=$run_args" \
  --env-file==a.env demo
assert "-E with a newline" "ERROR: --env-file value cannot span lines" \
  -E $'a\nb.env' demo
assert "-E without a task" \
  "Usage: lets [-E <file>|-S <name>|-e KEY=VALUE]... [--no-env-files] \
<task> [args...]" \
  -E a.env
assert "-E before --help" "ERROR: env flags apply to a task, not to --help" \
  -E a.env --help
assert "-e before --show" "ERROR: env flags apply to a task, not to --show" \
  -e A=1 --show
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
    "sources=unset no=unset vars=unset args=$run_args files=/abs/a.env" demo
  assert "relative -E from a directory with a colon" \
    "sources=file:$PWD/a.env no=unset vars=unset args=$run_args" -E a.env demo
  exit "$fail"
) || fail=1
assert "unknown flag" 'ERROR: unknown option "-x"' -x demo

builds() { cat "$stub/builds" 2>/dev/null | wc -l; }
fake="$stub/fake"
mkdir -p "$fake/bin"
cat >"$fake/bin/lets" <<EOF
#!$BASH
printf 'rebuilt vars=%s args=%s\n' "\${LETS_ENV_VARS-unset}" "\$*"
EOF
chmod +x "$fake/bin/lets"
STUB_BUILT="$fake" assert "unknown task: rebuilt lets takes over" \
  "rebuilt vars=unset args=__rebuilt nope x" nope x
STUB_BUILT="$fake" assert "unknown task: env flags passed once" \
  "rebuilt vars=A=1 args=__rebuilt nope" -e A=1 nope
assert "unknown task: build failure shows nix's error" \
  'stub: build failed
ERROR: unknown task "nope"' nope
before="$(builds)"
STUB_BUILT="$fake" assert "after a rebuild: unknown task reported" \
  'ERROR: unknown task "nope"' __rebuilt nope
if [ "$(builds)" = "$before" ]; then
  printf '  ✅ after a rebuild: no second build\n'
else
  printf '  ❌ after a rebuild: no second build\n'
  fail=1
fi
assert "after a rebuild: the task runs without the marker" \
  "$base args=$run_args x" __rebuilt demo x

if [ "$fail" = 0 ]; then
  echo "✅ wrapper assertions passed"
else
  echo "❌ wrapper assertions failed" >&2
fi
exit "$fail"
