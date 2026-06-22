#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: lets <task> [type] [-- task-args]" >&2
  exit 1
fi

task="$1"
shift

type=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
  type="$1"
  shift
fi

if [ -z "$type" ]; then
  target="$task"
else
  target="${task}_${type}"
fi

nix run --option warn-dirty false .#"$target" -- "$@"
