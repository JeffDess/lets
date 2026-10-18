#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2034,SC2088
set -euo pipefail

. "$1"
cd "$(mktemp -d)"
fail=0
declare -A ENV=() SCOPE=()
KEYS=()
RO=()

reset() {
  ENV=()
  SCOPE=()
  KEYS=()
  RO=()
}

expect() {
  if [ "$3" = "$2" ]; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1: expected [$2], got [$3]"
    fail=1
  fi
}

reset
printf '\xef\xbb\xbfA=1\r\nexport B="x y"\r\nC=${A}2\n' >bom.env
dotenv_eval bom.env 0 ENV SCOPE KEYS RO
expect "BOM, CRLF and export are accepted" "1|x y|12|A B C" \
  "${SCOPE[A]}|${SCOPE[B]}|${SCOPE[C]}|${KEYS[*]}"

reset
printf 'A=1\r\n' >one.env
printf 'A=1\r\nB="x y"\r\n\r\n' >last.env
dotenv_eval one.env 0 ENV SCOPE KEYS RO
expect "a CRLF on the only line is accepted" "1|A" "${SCOPE[A]}|${KEYS[*]}"
reset
dotenv_eval last.env 0 ENV SCOPE KEYS RO
expect "a CRLF after a quoted last value is accepted" "1|x y|A B" \
  "${SCOPE[A]}|${SCOPE[B]}|${KEYS[*]}"

reset
ENV=([PATH]=/bin)
RO=(PATH '_lets_*')
printf 'PATH=/evil\n_lets_x=1\nB=$PATH\nC=${PATH:=/x}\n' >ro.env
dotenv_eval ro.env 1 ENV SCOPE KEYS RO
expect "read-only names are skipped and resolve in ENV" \
  "unset|/bin|/bin|B C|1:PATH 2:_lets_x" \
  "${SCOPE[PATH]-unset}|${SCOPE[B]}|${SCOPE[C]}|${KEYS[*]}|${DOTENV_SKIPPED[*]}"

reset
SCOPE=([A]=0)
printf 'A=1\nB=$A\n' >seed.env
dotenv_eval seed.env 0 ENV SCOPE KEYS RO
expect "a pre-filled scope is replaced and read" "1|1" \
  "${SCOPE[A]}|${SCOPE[B]}"

reset
SCOPE=([A]=keep)
printf 'A=1\nB=$(echo x)\n' >partial.env
dotenv_eval partial.env 0 ENV SCOPE KEYS RO || true
expect "a file with an error sets nothing" \
  "keep|unset|2: command substitution and arithmetic are not supported" \
  "${SCOPE[A]}|${SCOPE[B]-unset}|$DOTENV_ERROR"

for form in '${#X}' '${X%p}' '${X#p}' '${X/a/b}' '${X:0:1}'; do
  reset
  ENV=([X]=pax)
  printf 'A=%s\n' "$form" >forbidden.env
  dotenv_eval forbidden.env 0 ENV SCOPE KEYS RO || true
  expect "$form is a parse error" "1:parse|unset" \
    "${DOTENV_ERROR%%:*}:$DOTENV_ERROR_KIND|${SCOPE[A]-unset}"
done

reset
printf 'A=${#X}\n' >length.env
dotenv_eval length.env 0 ENV SCOPE KEYS RO || true
expect '${#X} names what is unsupported' '1: ${#...} is not supported' \
  "$DOTENV_ERROR"

reset
printf 'A=1 export B=2\nexport export C=3\nexport=4\nexportD=5\n' >export.env
dotenv_eval export.env 0 ENV SCOPE KEYS RO
expect "export is a prefix anywhere a name starts, and a name otherwise" \
  "1|2|3|4|5|A B C export exportD" \
  "${SCOPE[A]}|${SCOPE[B]}|${SCOPE[C]}|${SCOPE[export]}|${SCOPE[exportD]}|\
${KEYS[*]}"
reset
printf 'export A\n' >export-bare.env
dotenv_eval export-bare.env 0 ENV SCOPE KEYS RO || true
expect "export without a value is a parse error" "1:parse" \
  "${DOTENV_ERROR%%:*}:$DOTENV_ERROR_KIND"

reset
touch match-me
printf 'A=~/x\nB=~\nC=*\nD=match-*\n' >literal.env
dotenv_eval literal.env 0 ENV SCOPE KEYS RO
expect "tilde and globs stay literal" "~/x|~|*|match-*" \
  "${SCOPE[A]}|${SCOPE[B]}|${SCOPE[C]}|${SCOPE[D]}"

for f in 'A=a\0b\n' 'A=1\0'; do
  reset
  printf '%b' "$f" >nul.env
  dotenv_eval nul.env 0 ENV SCOPE KEYS RO || true
  expect "a NUL byte fails the file" \
    "0: the file contains NUL bytes|read|unset" \
    "$DOTENV_ERROR|$DOTENV_ERROR_KIND|${SCOPE[A]-unset}"
done

reset
printf 'A=1\nBROKEN\nB=2\n' >noeq.env
dotenv_eval noeq.env 0 ENV SCOPE KEYS RO || true
expect "an error ended by a newline names its own line" \
  "2: expected '=' after the name" "$DOTENV_ERROR"

reset
printf 'A=${B:?set B first}\n' >required.env
dotenv_eval required.env 0 ENV SCOPE KEYS RO || true
expect "a required value names its message" "1: set B first|required" \
  "$DOTENV_ERROR|$DOTENV_ERROR_KIND"

reset
printf 'S=hunter2\nR=${R:?bad $S}\nT=${T:?$S}\n' >message.env
dotenv_eval message.env 0 ENV SCOPE KEYS RO || true
expect "a required message keeps only its literal text" "2: bad |no" \
  "$DOTENV_ERROR|$([[ $DOTENV_ERROR == *hunter2* ]] && echo yes || echo no)"
reset
printf 'S=hunter2\nT=${T:?${S:-x}$S}\n' >message.env
dotenv_eval message.env 0 ENV SCOPE KEYS RO || true
expect "a message made only of expansions names the variable" \
  "2: T is required" "$DOTENV_ERROR"

reset
declare -A PROBE=()
ENV=([X]=caller)
SCOPE=([X]=seeded)
dotenv_eval_string 'X=${X:-d}' 0 ENV SCOPE KEYS RO PROBE
expect "a self-default probes to its default" "caller|d" \
  "${SCOPE[X]}|${PROBE[X]}"

reset
PROBE=([stale]=1)
ENV=([A]=5 [B]=5x)
dotenv_eval_string $'A=1\nB=${A}x\nC=$A' 0 ENV SCOPE KEYS RO PROBE
expect "a derived value probes with the other names as usual" \
  "1|5x|5|2|unset unset" \
  "${PROBE[A]}|${PROBE[B]}|${SCOPE[C]}|${#PROBE[@]}|${PROBE[C]-unset} \
${PROBE[stale]-unset}"

reset
PROBE=()
ENV=([R]=r)
dotenv_eval_string 'R=${R:?set R}' 0 ENV SCOPE KEYS RO PROBE
expect "a required probe gives no entry and no error" "r|unset|" \
  "${SCOPE[R]}|${PROBE[R]-unset}|$DOTENV_ERROR"

reset
PROBE=()
ENV=([X]=e)
dotenv_eval_string 'X=${X:=d}${Y:=y}' 0 ENV SCOPE KEYS RO PROBE
expect "assignments inside a probe are suppressed" "e|dy|unset|X" \
  "${SCOPE[X]}|${PROBE[X]}|${SCOPE[Y]-unset}|${KEYS[*]}"

reset
PROBE=()
ENV=([X]=e)
dotenv_eval_string 'X=${X:-d}' 1 ENV SCOPE KEYS RO PROBE
expect "OVERRIDE=1 probes nothing" "e|0" "${SCOPE[X]}|${#PROBE[@]}"

reset
PROBE=()
declare -A FIXED=([X]=1 [Z]=1)
ENV=([X]=e [Y]=f)
dotenv_eval_string $'X=file\nY=file\nZ=file\nW=$X$Y$Z' 1 ENV SCOPE KEYS RO \
  PROBE FIXED
expect "OVERRIDE=1 keeps FIXED names that are in ENV" \
  "e|file|file|efilefile|X Y Z W" \
  "${SCOPE[X]}|${SCOPE[Y]}|${SCOPE[Z]}|${SCOPE[W]}|${KEYS[*]}"

reset
printf 'S=s3cr3t|x\n' >leak.env
dotenv_eval leak.env 0 ENV SCOPE KEYS RO || true
expect "errors never contain the value" "parse|no" \
  "$DOTENV_ERROR_KIND|$([[ $DOTENV_ERROR == *s3cr3t* ]] && echo yes || echo no)"

reset
printf 'A =1\n' >space.env
dotenv_eval space.env 0 ENV SCOPE KEYS RO || true
expect "whitespace before = fails" "1: expected '=' right after the name" \
  "$DOTENV_ERROR"

reset
printf 'T=s3cr3t\n' >traced.env
{
  set -x
  dotenv_eval traced.env 0 ENV SCOPE KEYS RO
  set +x
} 2>trace
traced="$(grep -q dotenv_eval trace && echo yes || echo no)"
leaked="$(grep -q s3cr3t trace && echo yes || echo no)"
expect "values never reach xtrace" "yes|no" "$traced|$leaked"

reset
dotenv_eval <(printf '%s\n' 'TOKEN="a b"' "PW='pa\$word'") 0 ENV SCOPE \
  KEYS RO
expect "a process substitution is read" 'a b|pa$word' \
  "${SCOPE[TOKEN]}|${SCOPE[PW]}"

reset
dotenv_eval_string 'A="x y" B=$A' 0 ENV SCOPE KEYS RO
expect "dotenv_eval_string evaluates text" "x y|x y" \
  "${SCOPE[A]}|${SCOPE[B]}"

reset
ENV=([A]=env)
printf 'A=file\nB=$A\n' >kept.env
dotenv_eval kept.env 0 ENV SCOPE KEYS RO
expect "without override, ENV wins and is read first" "env|env|A B" \
  "${SCOPE[A]}|${SCOPE[B]}|${KEYS[*]}"

: >empty.env
printf '\n\n' >newlines.env
for f in empty.env newlines.env; do
  expect "$f evaluates to nothing" "ok 0 keep" \
    "$(bash -c '. "$1"
      declare -A E=() S=([A]=keep)
      K=() R=()
      dotenv_eval "$2" 0 E S K R && echo "ok ${#K[@]} ${S[A]}" ||
        echo "fail: $DOTENV_ERROR"' _ "$1" "$f")"
done
expect "an empty string evaluates to nothing" "ok 0 keep" \
  "$(bash -c '. "$1"
    declare -A E=() S=([A]=keep)
    K=() R=()
    dotenv_eval_string "" 0 E S K R && echo "ok ${#K[@]} ${S[A]}" ||
      echo "fail: $DOTENV_ERROR"' _ "$1")"
expect "a failed parse does not leak into the next call" "ok 0 keep" \
  "$(bash -c '. "$1"
    declare -A E=() S=([A]=keep)
    K=() R=()
    dotenv_eval_string "A=\$(x)" 0 E S K R || true
    K=()
    dotenv_eval_string "" 0 E S K R && echo "ok ${#K[@]} ${S[A]}" ||
      echo "fail: $DOTENV_ERROR"' _ "$1")"

if [ "$fail" = 0 ]; then
  echo "✅ dotenv extensions pass"
else
  echo "❌ dotenv extensions fail"
  exit 1
fi
