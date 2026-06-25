#compdef lets
_lets() {
  local -a lines specs
  local l
  lines=( ${(f)"$(lets __complete "${(@)words[1,CURRENT]}" 2>/dev/null)"} )
  # Each line is `value<TAB>description`; _describe wants `value:description`.
  for l in $lines; do specs+=( "${l/$'\t'/:}" ); done
  _describe -t lets 'lets' specs
}
# Works both ways: autoloaded from $fpath as `_lets`, or sourced into a shell.
if [ "${funcstack[1]}" = "_lets" ]; then
  _lets "$@"
else
  compdef _lets lets
fi
