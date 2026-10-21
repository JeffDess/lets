#!/usr/bin/env bash

if [ ! -d tests/units ]; then
  echo "Error: tests/units not found; run from the repository root" >&2
  exit 1
fi

rc=0

mapfile -t untracked < <(git ls-files --others --exclude-standard -- tests)
if [ "${#untracked[@]}" -gt 0 ]; then
  warn "Untracked files are skipped until added to git:"
  printf '  %s\n' "${untracked[@]}"
  warn "Run: git add -N tests"
  echo
fi

echo "${BOLD}${UNDERLINE}${BLUE}Unit tests${RESET}"

system=$(nix eval --impure --raw --expr builtins.currentSystem)

if ! nix-unit --flake ".#tests.systems.$system"; then
  rc=1
fi

echo
echo "${BOLD}${UNDERLINE}${BLUE}Shell tests${RESET}"

if out=$(nix build --no-link --print-out-paths --option warn-dirty false \
  ".#checks.$system.shell"); then
  cat "$out"
else
  rc=1
fi

echo
echo "${BOLD}${UNDERLINE}${BLUE}Examples${RESET}"

if out=$(nix build --no-link --print-out-paths --option warn-dirty false \
  ".#checks.$system.examples"); then
  cat "$out"
else
  rc=1
fi

exit "$rc"
