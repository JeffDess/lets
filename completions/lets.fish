function __lets_complete
    set -l tokens (commandline -opc)
    set -l cur (commandline -ct)
    lets __complete $tokens "$cur" 2>/dev/null
end
complete -c lets -f -a '(__lets_complete)'
