#!/usr/bin/env fish

set lets_bin $argv[1]
set comp_file $argv[2]
set -x PATH (dirname $lets_bin) $PATH
source $comp_file

set fail 0
set tasks "demo greet lint lint_nix lint_nix-bash nix_lint version"
set top "demo greet lint nix version"

function check
    set -l desc $argv[1]
    set -l expected $argv[2]
    set -l cmdline $argv[3]
    set -l got (complete -C "$cmdline" \
        | string split -f1 \t | sort | string join ' ')
    set -l want (string split ' ' -- $expected | sort | string join ' ')
    if test "$got" = "$want"
        echo "  ✅ $desc"
    else
        echo "  ❌ $desc"
        echo "     expected: [$want]"
        echo "     got:      [$got]"
        set fail 1
    end
end

check "lets <TAB>" $top 'lets '
check "lets lint <TAB>" "nix nix-bash" 'lets lint '
check "lets lint -<TAB>" "--verbose -v" 'lets lint -'
check "lets version --<TAB>" "--dry-run" 'lets version --'
check "lets --help <TAB>" $tasks 'lets --help '
check "lets --completions <TAB>" "bash fish nushell zsh" 'lets --completions '
check "lets --show <TAB>" $tasks 'lets --show '
check "lets --show li<TAB>" "lint lint_nix lint_nix-bash" 'lets --show li'
check "lets -E .prod.env <TAB>" $top 'lets -E .prod.env '
mkdir -p envdir-fish; and cd envdir-fish; and touch .prod.env .dev.env
check "lets -E <TAB> lists files" ".dev.env .prod.env" 'lets -E '
touch .prod.enc.env .dev.enc.env
check "lets -S <TAB> lists secret names" "dev prod" 'lets -S '
check "lets -e <TAB> offers nothing" "" 'lets -e '
check "lets --no-env-files <TAB>" $top 'lets --no-env-files '
check "lets --secret=d<TAB>" "--secret=dev" 'lets --secret=d'
check "lets --env-file=.d<TAB>" "--env-file=.dev.enc.env --env-file=.dev.env" \
    'lets --env-file=.d'
set root_flags "--completions --env --env-file --help --no-env-files --secret"
set root_flags "$root_flags --show --version -E -S -c -e -h -s -v"
check "lets -<TAB> lists env flags" $root_flags 'lets -'
check "lets demo --locale <TAB>" "" 'lets demo --locale '

if test $fail -eq 0
    echo "✅ fish completion assertions passed"
else
    echo "❌ fish completion assertions failed" >&2
end
exit $fail
