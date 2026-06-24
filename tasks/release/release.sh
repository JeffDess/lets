#!/usr/bin/env bash
# shellcheck disable=SC2154

export RUST_LOG="${RUST_LOG:-error}"

tag="${GITHUB_REF_NAME:-}"
if [ -z "$tag" ]; then
  tag=$(git describe --tags --exact-match HEAD 2>/dev/null || true)
fi
if [ -z "$tag" ]; then
  echo "Error: no tag found (HEAD is untagged, GITHUB_REF_NAME unset)" >&2
  exit 1
fi

version=$(sed -n -E 's/^[[:space:]]*version = "([^"]+)";.*/\1/p' flake.nix)
if [ "$tag" != "v$version" ]; then
  echo "Error: tag $tag does not match flake.nix version v$version" >&2
  exit 1
fi

notes=$(git cliff --current --strip header | sed '/^## \[/d' | sed '/./,$!d')

if [ "$dry_run" = true ]; then
  printf "Release %s (dry-run, nothing published)\n\n" "$tag"
  if [ -n "$_lets_color" ]; then
    printf "%s\n" "$notes" | glow -
  else
    printf "%s\n" "$notes"
  fi
  exit 0
fi

printf "%s" "$notes" | gh release create "$tag" --title "$tag" --notes-file -
