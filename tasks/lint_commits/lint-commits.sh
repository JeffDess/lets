#!/usr/bin/env bash
# shellcheck disable=SC2154

fixup_pattern='^(fixup|squash|amend)! '
count=0
failed=0

fixups_allowed() {
  if [[ $allow_fixup == true ]]; then
    return 0
  fi
  # NOTE: An unknown push target counts as protected.
  local target=${PRE_COMMIT_REMOTE_BRANCH:-}
  [[ -n $protect && -n $target && $target != "refs/heads/$protect" ]]
}

lint_message() {
  local subject=$1 message=$2
  if [[ $subject =~ $fixup_pattern ]]; then
    if fixups_allowed; then
      echo "SKIP  -  $subject"
      return 0
    fi
    echo "FAIL  -  must be squashed before merging  $subject"
    return 1
  fi
  convco check --from-stdin --strip <<<"$message"
}

record() {
  count=$((count + 1))
  if ! lint_message "$1" "$2"; then
    failed=$((failed + 1))
  fi
}

if [[ -n $message_file ]]; then
  if [[ ! -r $message_file ]]; then
    error "cannot read message file: $message_file"
    exit 1
  fi
  message=$(<"$message_file")
  subject=$(git stripspace --strip-comments <<<"$message" | sed -n 1p)
  record "$subject" "$message"
else
  for ref in "$from" "$to"; do
    if [[ -n $ref ]] &&
      ! git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
      error "unknown revision: $ref"
      exit 1
    fi
  done
  if [[ -z $from ]]; then
    from=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$to" \
      2>/dev/null || true)
  fi
  while read -r sha; do
    record "$(git log -1 --format=%s "$sha")" \
      "$(git log -1 --format=%B "$sha")"
  done < <(git rev-list --reverse --no-merges "${from:+$from..}$to")
fi

if [[ $failed -gt 0 ]]; then
  error "$failed of $count commit(s) failed"
  exit 1
fi
echo "✅ Commit linter passed ($count commit(s))"
