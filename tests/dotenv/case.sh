#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034
set -euo pipefail

. "$1"
declare -A ENV=() SCOPE=()
KEYS=()
RO=()
while IFS= read -r -d '' k && IFS= read -r -d '' v; do
  ENV["$k"]="$v"
done <"$3"
if ! dotenv_eval "$2" "$4" ENV SCOPE KEYS RO; then
  printf %s "$DOTENV_ERROR_KIND" >"$5"
  exit 3
fi
for k in "${!SCOPE[@]}"; do
  printf '%s\0%s\0' "$k" "${SCOPE[$k]}"
done >"$5"
