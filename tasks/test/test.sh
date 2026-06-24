#!/usr/bin/env bash

if [ ! -f tests/mkTask.nix ]; then
  echo "Error: tests/mkTask.nix not found; run from the repository root" >&2
  exit 1
fi

results=$(
  nix eval --impure --json \
    --option warn-dirty false \
    --expr 'import ./tests/report.nix'
)

echo "${BOLD}${UNDERLINE}${BLUE}Unit tests${RESET}"

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
passed=$((total - failed))

echo

if [ "$failed" -eq 0 ]; then
  echo "✅ ${passed}/${total} passed"
else
  echo "❌ ${failed}/${total} failed" >&2
  exit 1
fi
