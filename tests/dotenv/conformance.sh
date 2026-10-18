#!/usr/bin/env bash
set -uo pipefail

module="$1"
cases="$2"
here="$(dirname "$0")"
tmp="$(mktemp -d)"
pass=0
fail=0
while IFS= read -r c; do
  desc="$(jq -r '.desc' <<<"$c")"
  jq -j '.input' <<<"$c" >"$tmp/input"
  jq -j '(.env // {}) | to_entries[] | "\(.key)\u0000\(.value)\u0000"' \
    <<<"$c" >"$tmp/env"
  override="$(jq -r 'if .override then 1 else 0 end' <<<"$c")"
  error="$(jq -r '.error // ""' <<<"$c")"
  bash "$here/case.sh" "$module" "$tmp/input" "$tmp/env" "$override" \
    "$tmp/out"
  status=$?
  if [ "$status" = 0 ] && [ -z "$error" ]; then
    kv=()
    while IFS= read -r -d '' k && IFS= read -r -d '' v; do
      kv+=("$k" "$v")
    done <"$tmp/out"
    got="$(jq -nS '$ARGS.positional as $a
      | reduce range(0; $a | length; 2) as $i ({}; .[$a[$i]] = $a[$i + 1])' \
      --args "${kv[@]}")"
    if [ "$got" = "$(jq -S '.expected' <<<"$c")" ]; then
      pass=$((pass + 1))
      continue
    fi
    echo "  ❌ $desc: got $(jq -c . <<<"$got")"
  elif [ "$status" = 3 ]; then
    case "$error:$(<"$tmp/out")" in
    ParseError:parse | UndefinedVariable:required)
      pass=$((pass + 1))
      continue
      ;;
    esac
    echo "  ❌ $desc: expected ${error:-a result}, got $(<"$tmp/out")"
  else
    echo "  ❌ $desc: exited $status"
  fi
  fail=$((fail + 1))
done < <(find "$cases" -name '*.json' -print0 | sort -z | xargs -0 cat |
  jq -c '.[]')
if [ "$fail" = 0 ]; then
  echo "✅ dotenv-spec: $pass evaluation cases pass"
else
  echo "❌ dotenv-spec: $fail of $((pass + fail)) evaluation cases fail"
  exit 1
fi
