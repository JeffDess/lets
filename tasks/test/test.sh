#!/usr/bin/env bash

if [ ! -f tests/mkTask.nix ]; then
  echo "Error: tests/mkTask.nix not found; run from the repository root" >&2
  exit 1
fi

rc=0

echo "${BOLD}${UNDERLINE}${BLUE}Unit tests${RESET}"

system=$(nix eval --impure --raw --expr builtins.currentSystem)

if ! nix-unit --flake ".#tests.systems.$system"; then
  rc=1
fi

echo
echo "${BOLD}${UNDERLINE}${BLUE}Shell tests${RESET}"

for shell_test in tests/browse.sh tests/lint-commits.sh; do
  if ! bash "$shell_test"; then
    rc=1
  fi
done

echo
echo "${BOLD}${UNDERLINE}${BLUE}Examples${RESET}"

if out=$(nix build --no-link --print-out-paths --option warn-dirty false \
  ".#checks.$system.examples"); then
  cat "$out"
else
  rc=1
fi

exit "$rc"
