_lets() {
  local cur e i glue='' pre
  local -a line=() out
  COMPREPLY=()
  for ((i = 0; i <= COMP_CWORD; i++)); do
    e="${COMP_WORDS[i]}"
    if [ -n "$glue" ]; then
      line[-1]+="$e"
      glue=''
    elif [[ $e =~ ^[=:]+$ ]] && [ "${#line[@]}" -gt 1 ]; then
      line[-1]+="$e"
      glue=1
    else
      line+=("$e")
    fi
  done
  cur="${COMP_WORDS[COMP_CWORD]}"
  [[ ! $cur =~ ^[=:]+$ ]] || cur=''
  pre="${line[-1]%"$cur"}"
  # shellcheck disable=SC2162
  IFS= read 'line[-1]' <<<"${line[-1]}"
  mapfile -t out < <(lets __complete "${line[@]}" 2>/dev/null)
  for e in "${out[@]}"; do
    e="${e%%$'\t'*}"
    [[ $e == "$pre"* ]] || continue
    printf -v e '%q' "${e#"$pre"}"
    [[ $e == \\~/* ]] && e="${e#\\}"
    [[ $e == "$cur"* ]] && COMPREPLY+=("$e")
  done
  if [ "${#COMPREPLY[@]}" = 1 ] && [[ ${COMPREPLY[0]} == */ ]]; then
    compopt -o nospace 2>/dev/null
  fi
}
complete -F _lets lets
