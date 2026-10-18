#compdef lets
_lets() {
  local -a lines specs dirs
  local l v
  lines=( ${(f)"$(lets __complete "${(@)words[1,CURRENT]}" 2>/dev/null)"} )
  for l in $lines; do
    v="${${l%%$'\t'*}//:/\\:}"
    [[ $l == *$'\t'* ]] && v+=":${l#*$'\t'}"
    if [[ ${l%%$'\t'*} == */ ]]; then dirs+=( "$v" ); else specs+=( "$v" ); fi
  done
  _describe -t lets 'lets' specs -- dirs -S ''
}
# Works both ways: autoloaded from $fpath as `_lets`, or sourced into a shell.
if [ "${funcstack[1]}" = "_lets" ]; then
  _lets "$@"
else
  compdef _lets lets
fi
