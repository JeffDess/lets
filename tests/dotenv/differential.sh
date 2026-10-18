#!/usr/bin/env bash
# shellcheck disable=SC1003,SC1090,SC2016,SC2034
set -euo pipefail

. "$1"
cd "$(mktemp -d)"
fail=0
printf '%s\n' "A=a'b'\"c\"" >concat.env
printf 'A="multi\nline" B=x\\\ny\n' >lines.env
printf '%s\n' 'A=1 B=${A:+set} C=${Z:-${A}def} D="${Z-"q w"}"' >ops.env
printf 'A=é\\ ü C="tab\there" D=\\$HOME E="\\\\n"\n' >escapes.env
printf "A=x#y B=1 # c\nC='#'\n" >comments.env
printf '%s\n' 'A=${B=dflt} C=$B' >assign.env
printf 'A=x\\\n' >trailing.env
printf 'A=x\\' >trailing-eof.env
for f in *.env; do
  declare -A ENV=() SCOPE=()
  KEYS=()
  RO=()
  if ! dotenv_eval "$f" 1 ENV SCOPE KEYS RO; then
    echo "  ❌ $f: $DOTENV_ERROR"
    fail=1
    continue
  fi
  while read -r k; do
    set_in_bash="$(env -i "$BASH" -c '. "$1"; [ -z "${!2+x}" ] || echo 1' \
      _ "$f" "$k")"
    if [ "$set_in_bash" != "${SCOPE[$k]+1}" ]; then
      echo "  ❌ $f: bash and dotenv disagree on whether $k is set"
      fail=1
    fi
  done < <(LC_ALL=C grep -oE '[A-Za-z_][A-Za-z0-9_]*' "$f" | sort -u)
  for k in "${!SCOPE[@]}"; do
    want="$(env -i "$BASH" -c '. "$1"; printf %s "${!2}"' _ "$f" "$k")"
    if [ "${SCOPE[$k]}" != "$want" ]; then
      echo "  ❌ $f: $k is [${SCOPE[$k]}], bash gives [$want]"
      fail=1
    fi
  done
done
if [ "$fail" = 0 ]; then
  echo "✅ dotenv matches bash on the corpus"
else
  echo "❌ dotenv differs from bash"
  exit 1
fi
