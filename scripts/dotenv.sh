#!/usr/bin/env bash

_dotenv_fail() {
  # shellcheck disable=SC2034
  DOTENV_ERROR="$_dotenv_line: $2"
  DOTENV_ERROR_KIND="$1"
  return 1
}

_dotenv_parse() {
  _dotenv_fail parse "$1"
}

_dotenv_flush() {
  if [ -n "$_dotenv_buf" ]; then
    _dotenv_tk+=("${1:-C}")
    _dotenv_tv+=("$_dotenv_buf")
    _dotenv_tl+=("$_dotenv_line")
    _dotenv_buf=''
  fi
}

_dotenv_emit() {
  _dotenv_tk+=("$1")
  _dotenv_tv+=("${2:-}")
  _dotenv_tl+=("$_dotenv_line")
}

_dotenv_tokenize() {
  local s c state=list eof re=0 q=0 i=0 n rest nl=0
  local -a stack=() lines
  mapfile -t lines < <(printf '%s\n' "$1")
  s="${lines[0]}" n=${#s}
  _dotenv_buf='' _dotenv_line=1
  _dotenv_tk=() _dotenv_tv=() _dotenv_tl=()
  while :; do
    if [ "$re" = 1 ]; then
      re=0
    elif ((i < n)); then
      _dotenv_line=$((_dotenv_line + nl)) nl=0
      rest="${s:i}"
      case "$state" in
      comment)
        i=$n
        continue
        ;;
      sq)
        if [[ $rest =~ ^[^\']+ ]]; then
          _dotenv_buf+="${BASH_REMATCH[0]}"
          i=$((i + ${#BASH_REMATCH[0]}))
          continue
        fi
        ;;
      dq)
        if [[ $rest =~ ^[^\"\\\$\`]+ ]]; then
          _dotenv_buf+="${BASH_REMATCH[0]}"
          i=$((i + ${#BASH_REMATCH[0]}))
          continue
        fi
        ;;
      name)
        if [[ $rest =~ ^[A-Za-z0-9_]+ ]]; then
          _dotenv_buf+="${BASH_REMATCH[0]}"
          i=$((i + ${#BASH_REMATCH[0]}))
          continue
        fi
        ;;
      value)
        if [[ $rest =~ ^[^\ \	\\\'\"\$\`\|\&\;\<\>\(\)]+ ]]; then
          _dotenv_buf+="${BASH_REMATCH[0]}"
          i=$((i + ${#BASH_REMATCH[0]}))
          continue
        fi
        ;;
      esac
      c="${rest:0:1}"
      i=$((i + 1))
      eof=0
    elif ((_dotenv_line + nl < ${#lines[@]})); then
      _dotenv_line=$((_dotenv_line + nl)) nl=1
      c=$'\n'
      s="${lines[_dotenv_line]}" n=${#s} i=0
      eof=0
    else
      c='' eof=1
    fi
    case "$state" in
    list)
      if [ "$eof" = 1 ]; then
        _dotenv_emit EOF
        return 0
      fi
      case "$c" in
      ' ' | $'\t' | $'\n') ;;
      '#') state=comment ;;
      [A-Za-z_])
        _dotenv_buf+="$c"
        state=name
        ;;
      *) _dotenv_parse 'expected a variable name' || return ;;
      esac
      ;;
    comment)
      if [ "$eof" = 1 ]; then
        _dotenv_emit EOF
        return 0
      fi
      [ "$c" != $'\n' ] || state=list
      ;;
    name)
      case "$c" in
      [A-Za-z0-9_]) _dotenv_buf+="$c" ;;
      '=')
        _dotenv_flush A
        state=value
        ;;
      ' ' | $'\t')
        if [ "$_dotenv_buf" = export ]; then
          _dotenv_buf=''
          state=list
        else
          _dotenv_parse "expected '=' right after the name" || return
        fi
        ;;
      *)
        if [ "$eof" = 1 ] || [ "$c" = $'\n' ]; then
          _dotenv_parse "expected '=' after the name" || return
        fi
        _dotenv_parse 'invalid variable name' || return
        ;;
      esac
      ;;
    value)
      if [ "$eof" = 1 ]; then
        _dotenv_flush
        _dotenv_emit EOF
        return 0
      fi
      case "$c" in
      ' ' | $'\t' | $'\n')
        _dotenv_flush
        state=list
        ;;
      \\) state=value_esc ;;
      "'")
        stack+=(value)
        state=sq
        ;;
      '"')
        q=$((q + 1))
        stack+=(value)
        state=dq
        ;;
      \$)
        stack+=(value)
        state=dollar
        ;;
      '`') _dotenv_parse 'command substitution is not supported' || return ;;
      '|' | '&' | ';' | '<' | '>' | '(' | ')')
        _dotenv_parse 'unescaped shell character, quote the value' || return
        ;;
      *) _dotenv_buf+="$c" ;;
      esac
      ;;
    value_esc)
      if [ "$eof" = 1 ]; then
        _dotenv_buf+=$'\\'
        _dotenv_flush
        _dotenv_emit EOF
        return 0
      fi
      [ "$c" = $'\n' ] || _dotenv_buf+="$c"
      state=value
      ;;
    sq)
      if [ "$eof" = 1 ]; then
        _dotenv_parse 'unterminated single quote' || return
      fi
      if [ "$c" = "'" ]; then
        state="${stack[-1]}"
        unset 'stack[-1]'
      else
        _dotenv_buf+="$c"
      fi
      ;;
    dq)
      if [ "$eof" = 1 ]; then
        _dotenv_parse 'unterminated double quote' || return
      fi
      case "$c" in
      '`') _dotenv_parse 'command substitution is not supported' || return ;;
      '"')
        q=$((q - 1))
        state="${stack[-1]}"
        unset 'stack[-1]'
        ;;
      \\) state=dq_esc ;;
      \$)
        stack+=(dq)
        state=dollar
        ;;
      *) _dotenv_buf+="$c" ;;
      esac
      ;;
    dq_esc)
      if [ "$eof" = 1 ]; then
        _dotenv_parse 'unterminated double quote' || return
      fi
      case "$c" in
      $'\n') ;;
      '"' | \$ | '`' | \\) _dotenv_buf+="$c" ;;
      *) _dotenv_buf+="\\$c" ;;
      esac
      state=dq
      ;;
    dollar)
      case "$c" in
      [0-9@*#?\$!-])
        _dotenv_parse 'special parameters are not supported' || return
        ;;
      '(')
        _dotenv_parse 'command substitution and arithmetic are not supported' ||
          return
        ;;
      [A-Za-z_])
        _dotenv_flush
        _dotenv_buf+="$c"
        state=simple
        ;;
      '{')
        _dotenv_flush
        state=cstart
        ;;
      *)
        _dotenv_buf+='$'
        state="${stack[-1]}"
        unset 'stack[-1]'
        re=1
        ;;
      esac
      ;;
    simple)
      if [ "$eof" = 0 ] && [[ $c == [A-Za-z0-9_] ]]; then
        _dotenv_buf+="$c"
      else
        _dotenv_flush S
        state="${stack[-1]}"
        unset 'stack[-1]'
        re=1
      fi
      ;;
    cstart)
      case "$c" in
      [A-Za-z_])
        _dotenv_buf+="$c"
        state=complex
        ;;
      '#')
        # shellcheck disable=SC2016
        _dotenv_parse '${#...} is not supported' || return
        ;;
      [0-9@*?\$!-])
        _dotenv_parse 'special parameters are not supported' || return
        ;;
      *) _dotenv_parse 'invalid expansion' || return ;;
      esac
      ;;
    complex)
      case "$c" in
      [A-Za-z0-9_]) _dotenv_buf+="$c" ;;
      '}')
        _dotenv_flush S
        state="${stack[-1]}"
        unset 'stack[-1]'
        ;;
      ':')
        _dotenv_flush X
        _dotenv_buf=':'
        state=op
        ;;
      '?' | '=' | '+' | '-')
        _dotenv_flush X
        _dotenv_emit O "$c"
        state=expval
        ;;
      *) _dotenv_parse 'invalid expansion' || return ;;
      esac
      ;;
    op)
      case "$c" in
      '?' | '=' | '+' | '-')
        _dotenv_buf+="$c"
        _dotenv_flush O
        state=expval
        ;;
      *) _dotenv_parse 'invalid expansion' || return ;;
      esac
      ;;
    expval)
      if [ "$eof" = 1 ]; then
        _dotenv_parse $'unterminated ${' || return
      fi
      case "$c" in
      '`') _dotenv_parse 'command substitution is not supported' || return ;;
      '}')
        _dotenv_flush
        _dotenv_emit E
        state="${stack[-1]}"
        unset 'stack[-1]'
        ;;
      \\) state=expval_esc ;;
      \$)
        stack+=(expval)
        state=dollar
        ;;
      '"')
        q=$((q + 1))
        stack+=(expval)
        state=dq
        ;;
      "'")
        if [ "$q" -ne 0 ]; then
          _dotenv_buf+="$c"
        else
          stack+=(expval)
          state=sq
        fi
        ;;
      *) _dotenv_buf+="$c" ;;
      esac
      ;;
    expval_esc)
      if [ "$eof" = 1 ]; then
        _dotenv_parse $'unterminated ${' || return
      fi
      case "$c" in
      $'\n') ;;
      '"' | \$ | '`' | \\) _dotenv_buf+="$c" ;;
      *)
        [ "$q" -eq 0 ] || _dotenv_buf+=$'\\'
        _dotenv_buf+="$c"
        ;;
      esac
      state=expval
      ;;
    esac
  done
}

_dotenv_match() {
  local _dotenv_name="$1" _dotenv_pat
  shift
  for _dotenv_pat in "$@"; do
    # shellcheck disable=SC2053
    [[ $_dotenv_name == $_dotenv_pat ]] && return 0
  done
  return 1
}

_dotenv_readonly() {
  if [ -z "${_dotenv_rc[$1]+x}" ]; then
    _dotenv_rc["$1"]=0
    if _dotenv_match "$1" "${_dotenv_ro[@]}"; then
      _dotenv_rc["$1"]=1
    fi
  fi
  [ "${_dotenv_rc[$1]}" = 1 ]
}

_dotenv_resolve() {
  if [ "$1" = "$_dotenv_undef" ]; then
    return 1
  elif _dotenv_readonly "$1"; then
    [ -n "${_dotenv_env[$1]+x}" ] || return 1
    _dotenv_v="${_dotenv_env[$1]}"
  elif [ "$_dotenv_override" = 1 ] && [ -z "${_dotenv_fx[$1]+x}" ] &&
    [ -n "${_dotenv_s[$1]+x}" ]; then
    _dotenv_v="${_dotenv_s[$1]}"
  elif [ -n "${_dotenv_env[$1]+x}" ]; then
    _dotenv_v="${_dotenv_env[$1]}"
  elif [ -n "${_dotenv_s[$1]+x}" ]; then
    _dotenv_v="${_dotenv_s[$1]}"
  else
    return 1
  fi
}

_dotenv_assign() {
  if _dotenv_readonly "$1"; then
    DOTENV_SKIPPED+=("$_dotenv_line:$1")
    return 0
  fi
  if [ -z "${_dotenv_seen[$1]+x}" ]; then
    _dotenv_k+=("$1")
    _dotenv_seen["$1"]=1
  fi
  _dotenv_s["$1"]="$2"
}

_dotenv_expr() {
  local end="$1" eval="$2" acc='' name op set need inner ev="$2"
  [ -z "$_dotenv_lit" ] || ev=0
  while :; do
    _dotenv_line="${_dotenv_tl[_dotenv_p]}"
    case "${_dotenv_tk[_dotenv_p]}" in
    A | EOF)
      if [ "$end" = E ]; then
        _dotenv_parse $'unterminated ${' || return
      fi
      _dotenv_r="$acc"
      return 0
      ;;
    E)
      if [ "$end" != E ]; then
        _dotenv_parse 'invalid expansion' || return
      fi
      _dotenv_p=$((_dotenv_p + 1))
      _dotenv_r="$acc"
      return 0
      ;;
    C)
      [ "$eval" = 0 ] || acc+="${_dotenv_tv[_dotenv_p]}"
      _dotenv_p=$((_dotenv_p + 1))
      ;;
    S)
      if [ "$ev" = 1 ] && _dotenv_resolve "${_dotenv_tv[_dotenv_p]}"; then
        acc+="$_dotenv_v"
      fi
      _dotenv_p=$((_dotenv_p + 1))
      ;;
    X)
      name="${_dotenv_tv[_dotenv_p]}"
      op="${_dotenv_tv[_dotenv_p + 1]}"
      _dotenv_p=$((_dotenv_p + 2))
      set=0
      _dotenv_v=''
      if [ "$ev" = 1 ] && _dotenv_resolve "$name"; then
        set=1
        if [[ $op == :* && -z $_dotenv_v ]]; then
          set=0
        fi
      fi
      case "$op" in
      - | :- | = | := | \? | :\?) need=$((1 - set)) ;;
      + | :+) need=$set ;;
      esac
      [ "$ev" = 1 ] || need=0
      local saved="$_dotenv_v" lit="$_dotenv_lit"
      [[ $op != *\? ]] || _dotenv_lit=1
      _dotenv_expr E "$need" || return
      _dotenv_lit="$lit"
      inner="$_dotenv_r"
      _dotenv_v="$saved"
      if [ "$need" = 1 ]; then
        case "$op" in
        = | :=)
          [ -n "$_dotenv_probing" ] || _dotenv_assign "$name" "$inner"
          ;;
        \? | :\?)
          _dotenv_fail required "${inner:-$name is required}" || return
          ;;
        esac
        _dotenv_v="$inner"
      fi
      [ "$ev" = 0 ] || acc+="$_dotenv_v"
      ;;
    *) _dotenv_parse 'invalid expansion' || return ;;
    esac
  done
}

_dotenv_read() {
  local -n _dotenv_into="$2"
  local _dotenv_chunk='' _dotenv_nul=''
  _dotenv_into=''
  while IFS= read -rd '' _dotenv_chunk; do
    _dotenv_into+="$_dotenv_chunk" _dotenv_nul=1
  done <"$1" || return 1
  _dotenv_into+="$_dotenv_chunk"
  [ -z "$_dotenv_nul" ] || return 2
}

dotenv_eval() {
  local - _dotenv_text _dotenv_status=0
  set +x
  _dotenv_read "$1" _dotenv_text || _dotenv_status=$?
  if [ "$_dotenv_status" = 2 ]; then
    # shellcheck disable=SC2034
    DOTENV_ERROR='0: the file contains NUL bytes' DOTENV_ERROR_KIND=read
    return 1
  elif [ "$_dotenv_status" != 0 ]; then
    # shellcheck disable=SC2034
    DOTENV_ERROR='0: cannot read the file' DOTENV_ERROR_KIND=read
    return 1
  fi
  dotenv_eval_string "$_dotenv_text" "${@:2}"
}

dotenv_eval_string() {
  local - LC_ALL=C _dotenv_override="$2" _dotenv_src="$1" _dotenv_buf
  local _dotenv_p=0 _dotenv_r _dotenv_v _dotenv_name _dotenv_key _dotenv_line
  local _dotenv_at _dotenv_q _dotenv_undef='' _dotenv_probing='' _dotenv_lit=''
  local -n _dotenv_env="$3" _dotenv_out="$4" _dotenv_keys="$5" _dotenv_ro="$6"
  if [ -n "${7:-}" ]; then
    local -n _dotenv_pr="$7"
    _dotenv_pr=()
  fi
  if [ -n "${8:-}" ]; then
    local -n _dotenv_fx="$8"
  else
    local -A _dotenv_fx=()
  fi
  local -a _dotenv_k=() _dotenv_tk _dotenv_tv _dotenv_tl
  local -A _dotenv_s=() _dotenv_seen=() _dotenv_rc=()
  set +x
  # shellcheck disable=SC2034
  DOTENV_ERROR='' DOTENV_ERROR_KIND='' DOTENV_SKIPPED=()
  _dotenv_src="${_dotenv_src#$'\xef\xbb\xbf'}"
  _dotenv_src="${_dotenv_src//$'\r\n'/$'\n'}"
  _dotenv_src="${_dotenv_src%$'\r'}"
  _dotenv_tokenize "$_dotenv_src" || return
  for _dotenv_key in "${!_dotenv_out[@]}"; do
    _dotenv_s["$_dotenv_key"]="${_dotenv_out[$_dotenv_key]}"
  done
  while [ "${_dotenv_tk[_dotenv_p]}" = A ]; do
    _dotenv_name="${_dotenv_tv[_dotenv_p]}"
    _dotenv_at="${_dotenv_tl[_dotenv_p]}"
    _dotenv_p=$((_dotenv_p + 1))
    if _dotenv_readonly "$_dotenv_name"; then
      _dotenv_expr A 0 || return
      DOTENV_SKIPPED+=("$_dotenv_at:$_dotenv_name")
    elif [ -n "${_dotenv_env[$_dotenv_name]+x}" ] &&
      { [ "$_dotenv_override" != 1 ] ||
        [ -n "${_dotenv_fx[$_dotenv_name]+x}" ]; }; then
      _dotenv_q="$_dotenv_p"
      _dotenv_expr A 0 || return
      _dotenv_assign "$_dotenv_name" "${_dotenv_env[$_dotenv_name]}"
      [ -z "${7:-}" ] || _dotenv_probe "$_dotenv_name" "$_dotenv_q"
    else
      _dotenv_expr A 1 || return
      _dotenv_assign "$_dotenv_name" "$_dotenv_r"
    fi
  done
  if [ "${_dotenv_tk[_dotenv_p]}" != EOF ]; then
    _dotenv_line="${_dotenv_tl[_dotenv_p]}"
    _dotenv_parse 'invalid expansion' || return
  fi
  for _dotenv_key in "${!_dotenv_s[@]}"; do
    _dotenv_out["$_dotenv_key"]="${_dotenv_s[$_dotenv_key]}"
  done
  _dotenv_keys=("${_dotenv_k[@]}")
}

_dotenv_probe() {
  local _dotenv_end="$_dotenv_p" _dotenv_undef="$1" _dotenv_probing=1
  local _dotenv_lit=''
  _dotenv_p="$2"
  if _dotenv_expr A 1; then
    _dotenv_pr["$1"]="$_dotenv_r"
  fi
  # shellcheck disable=SC2034
  DOTENV_ERROR='' DOTENV_ERROR_KIND=''
  _dotenv_p="$_dotenv_end"
}
