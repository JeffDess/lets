#!/usr/bin/env bash
set -uo pipefail

lets_bin="$1"
comp_file="$2"
bin_dir="$(dirname "$lets_bin")"
fail=0

check() {
  local desc="$1" expected="$2" spans="$3"
  local got
  got=$(nu --no-config-file -c "
    \$env.PATH = (\$env.PATH | prepend '$bin_dir')
    source '$comp_file'
    do \$env.config.completions.external.completer $spans
      | get value | sort | str join ' '
  " 2>/dev/null)
  if [ "$got" = "$expected" ]; then
    printf '  ✅ %s\n' "$desc"
  else
    printf '  ❌ %s\n' "$desc"
    printf '     expected: [%s]\n' "$expected"
    printf '     got:      [%s]\n' "$got"
    fail=1
  fi
}

tasks="demo lint lint_nix lint_nix-bash version"
shells="bash fish nushell zsh"
check "lets <TAB>" "demo lint version" "['lets' '']"
check "lets lint <TAB>" "nix nix-bash" "['lets' 'lint' '']"
check "lets lint -<TAB>" "--verbose -v" "['lets' 'lint' '-']"
check "lets version --<TAB>" "--dry-run" "['lets' 'version' '--']"
check "lets --help <TAB>" "$tasks" "['lets' '--help' '']"
check "lets --completions <TAB>" "$shells" "['lets' '--completions' '']"
check "lets --show <TAB>" "$tasks" "['lets' '--show' '']"

if [ "$fail" = 0 ]; then
  echo "✅ nushell completion assertions passed"
else
  echo "❌ nushell completion assertions failed" >&2
fi
exit "$fail"
