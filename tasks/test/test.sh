#!/usr/bin/env bash

if [ ! -f tests/mkTask.nix ]; then
  echo "Error: tests/mkTask.nix not found; run from the repository root" >&2
  exit 1
fi

rc=0

echo "${BOLD}${UNDERLINE}${BLUE}Unit tests${RESET}"

results=$(
  nix eval --impure --json \
    --option warn-dirty false \
    --expr 'import ./tests/report.nix'
)

rows=$(jq -r '.[]|[(.ok|tostring),.name,.expected,.got]|@tsv' <<<"$results")

while IFS=$'\t' read -r ok name expected got; do
  if [ "$ok" = true ]; then
    printf '  ✅ %s\n' "$name"
  else
    printf '  ❌ %s (expected %s, got %s)\n' "$name" "$expected" "$got"
  fi
done <<<"$rows"

total=$(jq 'length' <<<"$results")
failed=$(jq '[.[]|select(.ok|not)]|length' <<<"$results")

if [ "$failed" -eq 0 ]; then
  echo "✅ $((total - failed))/${total} passed"
else
  echo "❌ ${failed}/${total} failed"
  rc=1
fi

echo
echo "${BOLD}${UNDERLINE}${BLUE}Examples${RESET}"

system=$(nix eval --impure --raw --expr builtins.currentSystem)

if out=$(nix build --no-link --print-out-paths --option warn-dirty false \
  ".#checks.$system.examples"); then
  cat "$out"
else
  rc=1
fi

exit "$rc"
