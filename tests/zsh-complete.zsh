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
  local an e
  for an in "$@"; do
    for e in "${(@P)an}"; do CAP+=("${e%%:*}"); done
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

assert "lets <TAB>" "demo help lint show version" lets ""
assert "lets lint <TAB>" "nix nix-bash" lets lint ""
assert "lets lint -<TAB>" "--verbose -v" lets lint "-"
assert "lets version --<TAB>" "--dry-run" lets version "--"
assert "lets help --task <TAB>" "$tasks" lets help --task ""
assert "lets --completions <TAB>" "bash fish nushell zsh" lets --completions ""
assert "lets show <TAB>" "$tasks" lets show ""
assert "lets demo --locale <TAB>" "" lets demo --locale ""

if (( fail == 0 )); then
  print "✅ zsh completion assertions passed"
else
  print "❌ zsh completion assertions failed" >&2
fi
exit $fail
