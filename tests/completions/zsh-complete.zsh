#!/usr/bin/env zsh
emulate -L zsh
setopt no_unset

lets_bin="$1"
comp_file="$2"
path=("${lets_bin:h}" $path)

typeset -ga CAP
compdef() { : }
# _describe -t <tag> <descr> <arrayname>...  with elements `value:description`.
_describe() {
  while [[ "$1" == -* ]]; do
    [[ "$1" == -t ]] && shift
    shift
  done
  shift
  local e v sep=$'\1'
  while (( $# )); do
    case "$1" in
    --) shift ;;
    -S) shift 2 ;;
    *)
      for e in "${(@P)1}"; do
        v="${e//\\:/$sep}"
        CAP+=("${${v%%:*}//$sep/:}")
      done
      shift
      ;;
    esac
  done
}

# shellcheck disable=SC1090
source "$comp_file"

fail=0
tasks="demo lint lint_nix lint_nix-bash version"
assert() {
  local desc="$1" expected="$2"
  shift 2
  set -A words "$@"
  integer CURRENT=$#words
  CAP=()
  _lets
  local got="${CAP[*]}"
  if [[ "$got" == "$expected" ]]; then
    print "  ✅ $desc"
  else
    print "  ❌ $desc"
    print "     expected: [$expected]"
    print "     got:      [$got]"
    fail=1
  fi
}

assert "lets <TAB>" "demo lint version" lets ""
assert "lets lint <TAB>" "nix nix-bash" lets lint ""
assert "lets lint -<TAB>" "--verbose -v" lets lint "-"
assert "lets version --<TAB>" "--dry-run" lets version "--"
assert "lets --help <TAB>" "$tasks" lets --help ""
assert "lets --completions <TAB>" "bash fish nushell zsh" lets --completions ""
assert "lets --show <TAB>" "$tasks" lets --show ""
mkdir -p colon/sub && touch colon/a:b.env
assert "lets -E colon/<TAB> keeps colons" "colon/a:b.env colon/sub/" \
  lets -E colon/
assert "lets --env-file=colon/a<TAB>" "--env-file=colon/a:b.env" \
  lets --env-file=colon/a
assert "lets -E .prod.env <TAB>" "demo lint version" lets -E .prod.env ""
mkdir -p envdir-zsh && cd envdir-zsh && touch .prod.env .dev.env
assert "lets -E <TAB> lists files" ".dev.env .prod.env" lets -E ""
touch .prod.enc.env .dev.enc.env
assert "lets -S <TAB> lists secret names" "dev prod" lets -S ""
assert "lets -e <TAB> offers nothing" "" lets -e ""
assert "lets --no-env-files <TAB>" "demo lint version" lets --no-env-files ""
assert "lets --secret=d<TAB>" "--secret=dev" lets --secret=d
assert "lets demo --locale <TAB>" "" lets demo --locale ""

if (( fail == 0 )); then
  print "✅ zsh completion assertions passed"
else
  print "❌ zsh completion assertions failed" >&2
fi
exit $fail
