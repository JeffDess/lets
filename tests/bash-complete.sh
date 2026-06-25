#!/usr/bin/env bash
set -uo pipefail

lets_bin="$1"
comp_file="$2"
PATH="$(dirname "$lets_bin"):$PATH"
export PATH
# shellcheck disable=SC1090
source "$comp_file"

fail=0
tasks="demo lint lint_nix lint_nix-bash version"

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

assert "lets <TAB>" "demo help lint show version" lets ""
assert "lets lint <TAB>" "nix nix-bash" lets lint ""
assert "lets lint nix-bash <TAB>" "" lets lint nix-bash ""
assert "lets lint -<TAB>" "--verbose -v" lets lint "-"
assert "lets version --<TAB>" "--dry-run" lets version "--"
assert "lets help --task <TAB>" "$tasks" lets help --task ""
assert "lets help -t <TAB>" "$tasks" lets help -t ""
assert "lets --completions <TAB>" "bash fish nushell zsh" lets --completions ""
assert "lets -c <TAB>" "bash fish nushell zsh" lets -c ""
assert "lets show <TAB>" "$tasks" lets show ""
assert "lets show li<TAB>" "lint lint_nix lint_nix-bash" lets show li
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
