#!/usr/bin/env bash
# shellcheck disable=SC2329
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$script_dir/../tasks/lint/lint-commits.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
results="$test_dir/results"
: >"$results"

# NOTE: Isolate from active Git configuration, identity and push context.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset PRE_COMMIT_FROM_REF PRE_COMMIT_TO_REF PRE_COMMIT_REMOTE_BRANCH

commit() { git commit -q --allow-empty --no-verify -m "$1"; }

tagged="$test_dir/tagged"
git init -q -b main "$tagged"
(
  cd "$tagged"
  commit "chore: init" && git tag v0.1.0
  commit "feat: add a" && git tag ok
  commit "fixup! feat: add a" && git tag fixup
  commit "bad message" && git tag bad
  commit "fix: last" && git tag tip
)

untagged="$test_dir/untagged"
git init -q -b main "$untagged"
(
  cd "$untagged"
  commit "bad start"
  commit "feat: one"
)

msg_ok="$test_dir/msg-ok"
printf 'feat: x\n\n# Please enter the commit message\n' >"$msg_ok"
msg_comment_first="$test_dir/msg-comment-first"
printf '# Please enter the commit message\nfeat: x\n' >"$msg_comment_first"
msg_bad="$test_dir/msg-bad"
printf 'bad msg\n' >"$msg_bad"
msg_fixup="$test_dir/msg-fixup"
printf 'fixup! feat: x\n' >"$msg_fixup"

shape="first line doesn't match \`<type>[optional scope]: <description>\`"
fail_fixup='FAIL  -  must be squashed before merging  fixup! feat: add a'
fail_bad="FAIL  -  $shape  bad message"
skip_fixup='SKIP  -  fixup! feat: add a'
passed() { printf '✅ Commit linter passed (%s commit(s))' "$1"; }

record() {
  local label=$1 problem=$2
  if [[ -z $problem ]]; then
    printf '  ✅ %s\n' "$label"
    echo pass >>"$results"
  else
    printf '  ❌ %s (%s)\n' "$label" "$problem"
    echo fail >>"$results"
  fi
}

mismatch() {
  local status=$1 expected_status=$2 expected_out=$3 expected_err=$4 out err
  out=$(<"$test_dir/out")
  err=$(<"$test_dir/err")
  if [[ $status != "$expected_status" ]]; then
    echo "status $status, expected $expected_status"
  elif [[ $out != "$expected_out" ]]; then
    echo "stdout was: $out"
  elif [[ -n $expected_err && $err != *"$expected_err"* ]] ||
    [[ -z $expected_err && -n $err ]]; then
    echo "stderr was: $err"
  fi
  return 0
}

check() (
  local label=$1 repo=$2 expected_status=$3 expected_out=$4 expected_err=$5
  shift 5
  local status=0 kv
  error() { printf 'ERROR: %s\n' "$*" >&2; }
  # shellcheck disable=SC2034
  from='' to=HEAD message_file='' allow_fixup=false protect=''
  for kv in "$@"; do
    declare -x "$kv"
  done
  cd "$repo"
  set +e
  (
    set -e
    # shellcheck disable=SC1090
    source "$script"
  ) >"$test_dir/out" 2>"$test_dir/err"
  status=$?
  set -e
  record "$label" \
    "$(mismatch "$status" "$expected_status" "$expected_out" "$expected_err")"
)

check_app() (
  local label=$1 repo=$2 expected_status=$3 expected_out=$4 expected_err=$5
  shift 5
  local status=0
  local -a envs=()
  while [[ $1 != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  cd "$repo"
  set +e
  env "${envs[@]}" lint_commits "$@" >"$test_dir/out" 2>"$test_dir/err"
  status=$?
  set -e
  record "$label" \
    "$(mismatch "$status" "$expected_status" "$expected_out" "$expected_err")"
)

### Range mode ###

check 'valid range' "$tagged" 0 "$(passed 1)" '' from=v0.1.0 to=ok
check 'fixup rejected by default' "$tagged" 1 "$fail_fixup" \
  '1 of 1 commit(s) failed' from=ok to=fixup
check '--allow-fixup skips fixups' "$tagged" 0 \
  "$skip_fixup"$'\n'"$(passed 1)" '' from=ok to=fixup allow_fixup=true
check '--protect main rejects fixups pushed to main' "$tagged" 1 \
  "$fail_fixup" '1 of 1 commit(s) failed' from=ok to=fixup protect=main \
  PRE_COMMIT_REMOTE_BRANCH=refs/heads/main
check '--protect main skips fixups pushed elsewhere' "$tagged" 0 \
  "$skip_fixup"$'\n'"$(passed 1)" '' from=ok to=fixup protect=main \
  PRE_COMMIT_REMOTE_BRANCH=refs/heads/feature
check '--protect main rejects fixups with an unknown target' "$tagged" 1 \
  "$fail_fixup" '1 of 1 commit(s) failed' from=ok to=fixup protect=main
check 'invalid message' "$tagged" 1 "$fail_bad" '1 of 1 commit(s) failed' \
  from=fixup to=bad
check 'all commits checked after a failure' "$tagged" 1 \
  "$fail_fixup"$'\n'"$fail_bad" '2 of 4 commit(s) failed' \
  from=v0.1.0 to=tip
check 'empty --from falls back to the latest v* tag' "$tagged" 1 \
  "$fail_fixup"$'\n'"$fail_bad" '2 of 4 commit(s) failed' to=tip
check 'no v* tag lints the whole history' "$untagged" 1 \
  "FAIL  -  $shape  bad start" '1 of 2 commit(s) failed'
check 'empty range' "$tagged" 0 "$(passed 0)" '' from=tip to=tip
check 'unknown revision' "$tagged" 1 '' 'unknown revision: nope' from=nope

### Message mode ###

check 'message file valid' "$tagged" 0 "$(passed 1)" '' \
  message_file="$msg_ok"
check 'message file with leading comments' "$tagged" 0 "$(passed 1)" '' \
  message_file="$msg_comment_first"
check 'message file invalid' "$tagged" 1 "FAIL  -  $shape  bad msg" \
  '1 of 1 commit(s) failed' message_file="$msg_bad"
check 'message file fixup rejected by default' "$tagged" 1 \
  'FAIL  -  must be squashed before merging  fixup! feat: x' \
  '1 of 1 commit(s) failed' message_file="$msg_fixup"
check 'message file fixup with --allow-fixup' "$tagged" 0 \
  'SKIP  -  fixup! feat: x'$'\n'"$(passed 1)" '' \
  message_file="$msg_fixup" allow_fixup=true
check '--message-file takes precedence over --from' "$tagged" 0 \
  "$(passed 1)" '' message_file="$msg_ok" from=nope
check 'unreadable message file' "$tagged" 1 '' \
  "cannot read message file: $test_dir/missing" \
  message_file="$test_dir/missing"

### Parser defaults (built app) ###

if command -v lint_commits >/dev/null; then
  check_app 'PRE_COMMIT_* refs are the default range' "$tagged" 0 \
    "$skip_fixup"$'\n'"$(passed 1)" '' \
    PRE_COMMIT_FROM_REF=ok PRE_COMMIT_TO_REF=fixup \
    PRE_COMMIT_REMOTE_BRANCH=refs/heads/feature -- --protect main
  check_app 'options override PRE_COMMIT_* refs' "$tagged" 0 \
    "$(passed 1)" '' PRE_COMMIT_FROM_REF=ok PRE_COMMIT_TO_REF=fixup \
    -- --from v0.1.0 --to ok
  check_app 'no option lints latest tag..HEAD' "$tagged" 1 \
    "$fail_fixup"$'\n'"$fail_bad" '2 of 4 commit(s) failed' --
else
  printf '  ⏭️ parser defaults (skipped: lint_commits not on PATH)\n'
fi

mapfile -t outcomes <"$results"
total=${#outcomes[@]}
failed=0
for outcome in "${outcomes[@]}"; do
  [[ $outcome == pass ]] || failed=$((failed + 1))
done

if [[ $failed -eq 0 ]]; then
  echo "✅ ${total}/${total} passed"
else
  echo "❌ ${failed}/${total} failed"
  exit 1
fi
