#!/usr/bin/env bash

if [ ! -f flake.nix ]; then
  echo "Error: flake.nix not found; run from the flake root" >&2
  exit 1
fi

nix flake update
if [ -f dev/flake.nix ]; then
  nix flake update --flake ./dev
fi

echo "✅ Flake inputs updated"
