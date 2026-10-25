#!/usr/bin/env bash
set -uo pipefail

lets_bin="$1"
comp_file="$2"
PATH="$(dirname "$lets_bin"):$PATH"
export PATH
# shellcheck disable=SC1090
source "$comp_file"

fail=0
tasks="demo greet lint lint_nix lint_nix-bash nix_lint version"
top="demo greet lint nix version"

assert() {
  local desc="$1" expected="$2"
  shift 2
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  _lets
  local got="${COMPREPLY[*]}"
  if [ "$got" = "$expected" ]; then
    printf '  ✅ %s\n' "$desc"
  else
    printf '  ❌ %s\n' "$desc"
    printf '     expected: [%s]\n' "$expected"
    printf '     got:      [%s]\n' "$got"
    fail=1
  fi
}

assert "lets <TAB>" "$top" lets ""
assert "lets lint <TAB>" "nix nix-bash" lets lint ""
assert "lets lint nix-bash <TAB>" "" lets lint nix-bash ""
assert "lets lint -<TAB>" "--verbose -v" lets lint "-"
assert "lets version --<TAB>" "--dry-run" lets version "--"
assert "lets --help <TAB>" "$tasks" lets --help ""
assert "lets -h <TAB>" "$tasks" lets -h ""
assert "lets --completions <TAB>" "bash fish nushell zsh" lets --completions ""
assert "lets -c <TAB>" "bash fish nushell zsh" lets -c ""
assert "lets --show <TAB>" "$tasks" lets --show ""
assert "lets -s <TAB>" "$tasks" lets -s ""
assert "lets --show li<TAB>" "lint lint_nix lint_nix-bash" lets --show li
assert_sorted() {
  local desc="$1" expected="$2"
  shift 2
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  _lets
  local got
  got="$(printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ')"
  if [ "${got% }" = "$expected" ]; then
    printf '  ✅ %s\n' "$desc"
  else
    printf '  ❌ %s\n     expected: [%s]\n     got:      [%s]\n' \
      "$desc" "$expected" "${got% }"
    fail=1
  fi
}
root_flags="--completions --env --env-file --help --no-env-files --secret"
root_flags="$root_flags --show --version -E -S -c -e -h -s -v"
assert_sorted "lets -<TAB> lists env flags" "$root_flags" lets "-"
assert "lets -E .prod.env <TAB>" "$top" lets -E .prod.env ""
assert "lets --no-env-files <TAB>" "$top" lets --no-env-files ""
mkdir -p quoting/home && cd quoting || exit 1
# shellcheck disable=SC2016
touch '$(touch PWNED).env' 'a b.env' .p.env home/h.env
assert_sorted "lets -E <TAB> quotes file names" \
  '.p.env \$\(touch\ PWNED\).env a\ b.env home/' lets -E ""
if [ -e PWNED ]; then
  printf '  ❌ %s\n' "file names are never evaluated"
  fail=1
fi
assert 'lets -E a\ <TAB>' 'a\ b.env' lets -E 'a\ '
assert "lets --env-file=.p<TAB>" ".p.env" lets --env-file = .p
assert "lets --env-file=h<TAB>" "home/" lets --env-file = h
assert_sorted "lets --env-file=<TAB>" \
  '.p.env \$\(touch\ PWNED\).env a\ b.env home/' lets --env-file =
assert "lets --env-file=x lint <TAB>" "nix nix-bash" lets --env-file = x lint ""
home_was="$HOME"
export HOME="$PWD/home"
# shellcheck disable=SC2088
assert "lets -E ~/<TAB>" "~/h.env" lets -E "~/"
export HOME="$home_was"
cd .. || exit 1
assert "lets -E .prod.env lint <TAB>" "nix nix-bash" lets -E .prod.env lint ""
assert "lets lint -E x nix <TAB>" "nix nix-bash" lets lint -E x nix ""
assert "lets demo <TAB>" "alice bob" lets demo ""
assert "lets -E .prod.env demo <TAB>" "alice bob" lets -E .prod.env demo ""
assert "lets --env-file=x demo <TAB>" "alice bob" lets --env-file = x demo ""
assert "lets demo alice <TAB>" "" lets demo alice ""
assert "lets greet <TAB>" "alice bob" lets greet ""
assert "lets greet -<TAB>" "--locale -l" lets greet "-"
assert "lets nix <TAB>" "lint" lets nix ""
assert "lets --env=<TAB> offers nothing" "" lets --env =
assert "lets --env=A=1 <TAB>" "$top" lets --env = A = 1 ""
assert "lets lint -e x nix <TAB>" "nix nix-bash" lets lint -e x nix ""
mkdir -p envdir-bash slashdir/sub && cd envdir-bash && touch .prod.env .dev.env
assert_sorted "lets -E <TAB> lists files" ".dev.env .prod.env" lets -E ""
assert "lets -E ../slashdir/s<TAB>" "../slashdir/sub/" lets -E ../slashdir/s
assert "lets -E .p<TAB>" ".prod.env" lets -E ".p"
touch .prod.enc.env .dev.enc.env
assert_sorted "lets -S <TAB> lists secret names" "dev prod" lets -S ""
assert "lets -S d<TAB>" "dev" lets -S "d"
assert "lets -S dev <TAB>" "$top" lets -S dev ""
assert "lets --secret=d<TAB>" "dev" lets --secret = d
assert "lets --secret=dev <TAB>" "$top" lets --secret = dev ""
assert "lets lint -S x nix <TAB>" "nix nix-bash" lets lint -S x nix ""
mkdir -p project/sub && touch project/flake.nix project/.ci.enc.env
cd project/sub || exit 1
assert "lets -S <TAB> from a subdirectory" "ci" lets -S ""
cd ../.. || exit 1
assert "lets -e <TAB> offers nothing" "" lets -e ""
assert "lets -e A=1 <TAB>" "$top" lets -e A = 1 ""
assert "lets -E a -S b -e K=V --no-env-files <TAB>" "$top" \
  lets -E a -S b -e K = V --no-env-files ""
assert "lets -e A=1 demo <TAB>" "alice bob" lets -e A = 1 demo ""
assert "lets --env A=1 demo <TAB>" "alice bob" lets --env A = 1 demo ""
assert "lets -e A=1 lint <TAB>" "nix nix-bash" lets -e A = 1 lint ""
assert "lets -E a:b lint <TAB>" "nix nix-bash" lets -E a : b lint ""
assert "lets -S a:b lint <TAB>" "nix nix-bash" lets -S a : b lint ""
mkdir -p colon && touch 'colon/x:y.env'
assert "lets -E colon/x:<TAB>" "y.env" lets -E colon/x :
assert "lets -E colon/x:y<TAB>" "y.env" lets -E colon/x : y
assert "lets --env-file=a -S b demo <TAB>" "alice bob" \
  lets --env-file = a -S b demo ""
assert "lets -E a -S b -e <TAB> offers nothing" "" lets -E a -S b -e ""
assert "lets demo --locale <TAB>" "" lets demo --locale ""

# NOTE: Descriptions are emitted as a tab-separated second field.
assert_desc() {
  local value="$1" expected="$2"
  shift 2
  local got
  got=$(lets __complete "$@" | awk -F'\t' -v k="$value" '$1==k{print $2; exit}')
  if [ "$got" = "$expected" ]; then
    printf '  ✅ desc %s\n' "$value"
  else
    printf '  ❌ desc %s\n     expected: [%s]\n     got:      [%s]\n' \
      "$value" "$expected" "$got"
    fail=1
  fi
}
assert_desc "lint" "Run all lint tasks" lets ""
assert_desc "--dry-run" "Plan only" lets version "--"

if [ "$fail" = 0 ]; then
  echo "✅ bash completion assertions passed"
else
  echo "❌ bash completion assertions failed" >&2
fi
exit "$fail"
