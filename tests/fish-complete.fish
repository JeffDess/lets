#!/usr/bin/env fish

set lets_bin $argv[1]
set comp_file $argv[2]
set -x PATH (dirname $lets_bin) $PATH
source $comp_file

set fail 0
set tasks "demo lint lint_nix lint_nix-bash version"

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

check "lets <TAB>" "demo help lint show version" 'lets '
check "lets lint <TAB>" "nix nix-bash" 'lets lint '
check "lets lint -<TAB>" "--verbose -v" 'lets lint -'
check "lets version --<TAB>" "--dry-run" 'lets version --'
check "lets help --task <TAB>" $tasks 'lets help --task '
check "lets --completions <TAB>" "bash fish nushell zsh" 'lets --completions '
check "lets show <TAB>" $tasks 'lets show '
check "lets show li<TAB>" "lint lint_nix lint_nix-bash" 'lets show li'
check "lets demo --locale <TAB>" "" 'lets demo --locale '

if test $fail -eq 0
    echo "✅ fish completion assertions passed"
else
    echo "❌ fish completion assertions failed" >&2
end
exit $fail
