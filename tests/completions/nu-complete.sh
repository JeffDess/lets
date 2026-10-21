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
check "lets -E .prod.env <TAB>" "demo lint version" \
  "['lets' '-E' '.prod.env' '']"
mkdir -p envdir-nu && cd envdir-nu && touch .prod.env .dev.env
check "lets -E <TAB> lists files" ".dev.env .prod.env" "['lets' '-E' '']"
touch .prod.enc.env .dev.enc.env
check "lets -S <TAB> lists secret names" "dev prod" "['lets' '-S' '']"
check "lets -e <TAB> offers nothing" "" "['lets' '-e' '']"
check "lets --no-env-files <TAB>" "demo lint version" \
  "['lets' '--no-env-files' '']"
check "lets --secret=d<TAB>" "--secret=dev" "['lets' '--secret=d']"
check "lets --env-file=.d<TAB>" "--env-file=.dev.enc.env --env-file=.dev.env" \
  "['lets' '--env-file=.d']"
root_flags="--completions --env --env-file --help --no-env-files --secret"
root_flags="$root_flags --show --version -E -S -c -e -h -s -v"
check "lets -<TAB> lists env flags" "$root_flags" "['lets' '-']"

if [ "$fail" = 0 ]; then
  echo "✅ nushell completion assertions passed"
else
  echo "❌ nushell completion assertions failed" >&2
fi
exit "$fail"
