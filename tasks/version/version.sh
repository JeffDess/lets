#!/usr/bin/env bash
# shellcheck disable=SC2154

while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run) dry_run=true ;;
  *)
    echo "Error: unexpected argument '$1'" >&2
    exit 1
    ;;
  esac
  shift
done

current=$(sed -n -E 's/^[[:space:]]*version = "([^"]+)";.*/\1/p' flake.nix)
if [ -z "$current" ]; then
  echo "Error: could not read version from flake.nix" >&2
  exit 1
fi

if [ -z "$level" ]; then
  new=$(git cliff --bumped-version | sed 's/^v//')
  if [ -z "$new" ] || [ "$new" = "$current" ]; then
    echo "Error: no conventional commits to bump since the last release" >&2
    exit 1
  fi
else
  case "$level" in
  major | minor | patch | prerel | prerelease | release) ;;
  *)
    echo "Error: '$level' is not a valid level" >&2
    echo "Use major, minor, patch, prerel, release, or omit to auto-detect" >&2
    exit 1
    ;;
  esac
  new=$(semver bump "$level" "$current")
fi
tag="v$new"

if [ "$dry_run" = true ]; then
  printf "Would bump %s -> %s and tag %s\n\n" "$current" "$new" "$tag"
  notes=$(git cliff --unreleased --tag "$tag" --strip header | sed '/./,$!d')
  if [ -n "$_lets_color" ]; then
    printf "%s\n" "$notes" | glow -
  else
    printf "%s\n" "$notes"
  fi
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean; commit or stash changes first" >&2
  exit 1
fi

sed -i -E "s|^([[:space:]]*version = \")[^\"]+(\";)|\1${new}\2|" flake.nix
git cliff --tag "$tag" --output CHANGELOG.md
git add flake.nix CHANGELOG.md
git commit --message "chore(release): $tag"
git tag --annotate "$tag" --message "$tag"

printf "Bumped %s -> %s and tagged %s.\n" "$current" "$new" "$tag"
printf "Review, then run: git push --follow-tags\n"
