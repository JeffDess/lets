#!/usr/bin/env bash
set -uo pipefail

range=${1:-}
fixup_pattern='^(fixup|squash|amend)! '

if [[ -z $range ]]; then
  echo "Usage: ALLOW_FIXUP=true|false check-commits.sh <base>..<head>" >&2
  exit 2
fi

status=0

for sha in $(git rev-list --reverse --no-merges "$range"); do
  subject=$(git log -1 --format=%s "$sha")

  if [[ $subject =~ $fixup_pattern ]]; then
    if [[ ${ALLOW_FIXUP:-false} == true ]]; then
      echo "SKIP  -  $subject"
      continue
    fi

    echo "FAIL  -  must be squashed before merging  $subject"
    status=1
    continue
  fi

  git log -1 --format=%B "$sha" | convco check --from-stdin || status=1
done

exit $status
