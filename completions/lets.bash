_lets() {
  local cur e
  cur="${COMP_WORDS[COMP_CWORD]}"
  local -a line out vals=()
  line=("${COMP_WORDS[@]:0:COMP_CWORD+1}")
  mapfile -t out < <(lets __complete "${line[@]}" 2>/dev/null)
  for e in "${out[@]}"; do vals+=("${e%%$'\t'*}"); done
  mapfile -t COMPREPLY < <(compgen -W "${vals[*]}" -- "$cur")
}
complete -F _lets lets
