#!/bin/bash
# tests/test-land-pr-auto-rebase-behind.sh — regression tests for Issue #266.
#
# /land-pr Step 6b (`Auto-rebase BEHIND PRs post-CI-green`) was added to
# close the OPEN/BEHIND auto-merge stall gap. Without it, when a sibling
# PR lands between `pr-monitor.sh` returning CI=pass and `pr-merge.sh`
# requesting auto-merge, the feature branch goes BEHIND, GitHub's
# auto-merge waits indefinitely (on repos with "Require branches to be up
# to date" branch protection), and the orchestrator must manually rebase
# + force-push.
#
# This test has two layers:
#
#   1. Anchor regression guards — grep SKILL.md for sentinel strings that
#      MUST survive future edits. Failure means the Step 6b prose has
#      drifted and Issue #266 may have regressed.
#
#   2. Reference-implementation harness — mock `gh pr view`,
#      `pr-monitor.sh`, and the rebase/push git commands; exercise the
#      loop logic; assert it fires/skips correctly across the matrix.
#
# Mock approach: instead of running the SKILL.md bash directly (it depends
# on gh, real git remotes, and pr-monitor.sh), we extract the Step 6b
# logic into a `run_auto_rebase_block` function and drive it with mock
# command queues (gh_mock_queue, monitor_mock_queue, rebase_mock_queue,
# push_mock_queue) that return predetermined exit codes + outputs.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/land-pr/SKILL.md"

PASS=0
FAIL=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$SKILL_FILE" ]; then
  echo "FAIL: SKILL.md not found at $SKILL_FILE" >&2
  exit 1
fi

# ---- Layer 1: Anchor regression guards ------------------------------
# These sentinels are the load-bearing prose of Step 6b. Future edits to
# the skill MUST preserve them, or the Issue #266 fix has regressed.
for anchor in \
  'Step 6b — Auto-rebase BEHIND PRs post-CI-green (Issue #266)' \
  'AUTO_REBASE_MAX=3' \
  'mergeStateStatus' \
  'push --force-with-lease origin "$BRANCH"' \
  'STATUS="behind-thrash"' \
  'REASON="auto-rebase-exhausted"' \
  'STATUS="auto-rebase-conflict"' \
  'STATUS="auto-rebase-blocked"' \
  'REBASE_STDERR_FILE="$REBASE_STDERR"' \
  'CLEAN|HAS_HOOKS|UNSTABLE' \
  'BLOCKED|CONFLICTING'
do
  if ! grep -qF "$anchor" "$SKILL_FILE"; then
    fail "[anchor] SKILL.md missing Step 6b anchor: $anchor" "(Issue #266 regression)"
  else
    pass "[anchor] SKILL.md contains Step 6b anchor: $anchor"
  fi
done

# Result-file schema enumerations must include the new STATUS tokens.
for token in behind-thrash auto-rebase-conflict auto-rebase-blocked REBASE_STDERR_FILE; do
  if ! grep -qF "$token" "$SKILL_FILE"; then
    fail "[schema] SKILL.md schema missing token: $token" "(Issue #266 regression)"
  else
    pass "[schema] SKILL.md schema contains token: $token"
  fi
done

# Status mapping table must map the new STATUS values.
if ! grep -qE 'behind-thrash.*pr-ready' "$SKILL_FILE"; then
  fail "[mapping] STATUS=behind-thrash not mapped → pr-ready" "(Issue #266 regression)"
else
  pass "[mapping] STATUS=behind-thrash → pr-ready"
fi
if ! grep -qE 'auto-rebase-conflict.*conflict' "$SKILL_FILE"; then
  fail "[mapping] STATUS=auto-rebase-conflict not mapped → conflict" "(Issue #266 regression)"
else
  pass "[mapping] STATUS=auto-rebase-conflict → conflict"
fi
if ! grep -qE 'auto-rebase-blocked.*pr-ready' "$SKILL_FILE"; then
  fail "[mapping] STATUS=auto-rebase-blocked not mapped → pr-ready" "(Issue #266 regression)"
else
  pass "[mapping] STATUS=auto-rebase-blocked → pr-ready"
fi

# Step 7 merge gate must skip the new STATUS values.
for skip_status in behind-thrash auto-rebase-conflict auto-rebase-blocked; do
  if ! grep -qE "STATUS\" != \"$skip_status" "$SKILL_FILE"; then
    fail "[step7-skip] Step 7 merge gate doesn't skip STATUS=$skip_status" "(would attempt merge on BEHIND/conflict)"
  else
    pass "[step7-skip] Step 7 merge gate skips STATUS=$skip_status"
  fi
done

# ---- Layer 2: Reference-implementation harness ----------------------
# We extract the Step 6b control flow into a shell function and drive it
# with mocked command queues. Each test case sets up the queues, calls
# run_auto_rebase_block, and asserts on the resulting STATUS/REASON.
#
# Mock queue protocol: each queue is a file (one line per call). A wrapper
# function pops the head line, parses "exit-code|stdout-payload", and
# returns accordingly.

MOCKDIR=$(mktemp -d "/tmp/land-pr-auto-rebase-test.XXXXXX")
trap 'rm -rf "$MOCKDIR"' EXIT

# Mock queue files.
GH_QUEUE="$MOCKDIR/gh.queue"
MONITOR_QUEUE="$MOCKDIR/monitor.queue"
REBASE_QUEUE="$MOCKDIR/rebase.queue"
PUSH_QUEUE="$MOCKDIR/push.queue"
FETCH_QUEUE="$MOCKDIR/fetch.queue"

reset_queues() {
  : > "$GH_QUEUE"
  : > "$MONITOR_QUEUE"
  : > "$REBASE_QUEUE"
  : > "$PUSH_QUEUE"
  : > "$FETCH_QUEUE"
}

queue_push() {
  # $1=queue-file, $2=exit-code, $3=stdout-payload
  printf '%s|%s\n' "$2" "$3" >> "$1"
}

queue_pop() {
  # $1=queue-file → echoes "rc|payload" or "0|" if empty
  local q="$1"
  if [ ! -s "$q" ]; then
    echo "0|"
    return
  fi
  local head
  head=$(head -n1 "$q")
  tail -n +2 "$q" > "$q.tmp" && mv "$q.tmp" "$q"
  echo "$head"
}

# Mock command functions used by the reference implementation.
mock_gh_pr_view() {
  # Returns stdout (the JSON), exit code from queue.
  local entry rc payload
  entry=$(queue_pop "$GH_QUEUE")
  rc="${entry%%|*}"
  payload="${entry#*|}"
  printf '%s' "$payload"
  return "$rc"
}

mock_pr_monitor() {
  # Returns "CI_STATUS=X" lines on stdout, exit code from queue.
  local entry rc payload
  entry=$(queue_pop "$MONITOR_QUEUE")
  rc="${entry%%|*}"
  payload="${entry#*|}"
  printf '%s\n' "$payload"
  return "$rc"
}

mock_git_fetch()   { local entry rc; entry=$(queue_pop "$FETCH_QUEUE");  rc="${entry%%|*}"; return "$rc"; }
mock_git_rebase()  { local entry rc; entry=$(queue_pop "$REBASE_QUEUE"); rc="${entry%%|*}"; return "$rc"; }
mock_git_push()    { local entry rc; entry=$(queue_pop "$PUSH_QUEUE");   rc="${entry%%|*}"; return "$rc"; }
mock_git_rebase_abort() { return 0; }
mock_git_diff_unmerged() { echo "conflict-file.txt"; return 0; }

# Reference implementation of Step 6b — mirrors the SKILL.md bash logic
# 1:1, with gh / git / pr-monitor.sh replaced by mock_* shims.
run_auto_rebase_block() {
  # Inputs (env): STATUS, AUTO_FLAG, CI_STATUS, PR_NUMBER, BRANCH,
  #               BASE_BRANCH, WORKTREE_PATH, BRANCH_SLUG, CI_TIMEOUT
  # Outputs (env): STATUS, REASON, CI_STATUS, CONFLICT_FILES_LIST,
  #                REBASE_STDERR_FILE
  : "${BRANCH_SLUG:=test}"
  : "${CI_TIMEOUT:=600}"

  if [ -z "$STATUS" ] \
     && [ "$AUTO_FLAG" = "true" ] \
     && [ "$CI_STATUS" = "pass" ] \
     && [ -n "$PR_NUMBER" ]; then
    REBASE_STDERR="$MOCKDIR/rebase-stderr-$BRANCH_SLUG-$$.log"
    : > "$REBASE_STDERR"
    AUTO_REBASE_ITER=0
    AUTO_REBASE_MAX=3

    MS_JSON=$(mock_gh_pr_view)
    MS_STATE=""
    if [[ "$MS_JSON" =~ \"mergeStateStatus\":[[:space:]]*\"([^\"]+)\" ]]; then
      MS_STATE="${BASH_REMATCH[1]}"
    fi

    while [ "$MS_STATE" = "BEHIND" ] && [ "$AUTO_REBASE_ITER" -lt "$AUTO_REBASE_MAX" ]; do
      AUTO_REBASE_ITER=$((AUTO_REBASE_ITER + 1))

      if ! mock_git_fetch; then
        STATUS="auto-rebase-conflict"
        REASON="auto-rebase-fetch-failed-rc$?"
        break
      fi
      if ! mock_git_rebase; then
        CONFLICT_PATHS=$(mock_git_diff_unmerged | tr '\n' ' ' | sed 's/ $//')
        mock_git_rebase_abort || true
        if [ -n "$CONFLICT_PATHS" ]; then
          CONFLICT_FILES_SIDECAR="$MOCKDIR/conflicts-$BRANCH_SLUG-$$.list"
          printf '%s\n' $CONFLICT_PATHS > "$CONFLICT_FILES_SIDECAR"
          CONFLICT_FILES_LIST="$CONFLICT_FILES_SIDECAR"
        fi
        STATUS="auto-rebase-conflict"
        REASON="auto-rebase-conflict-iter$AUTO_REBASE_ITER"
        break
      fi

      if ! mock_git_push; then
        PUSH_RC=$?
        if [ "$AUTO_REBASE_ITER" -ge "$AUTO_REBASE_MAX" ]; then
          STATUS="auto-rebase-blocked"
          REASON="auto-rebase-push-failed-rc$PUSH_RC"
          break
        fi
        MS_JSON=$(mock_gh_pr_view)
        MS_STATE=""
        if [[ "$MS_JSON" =~ \"mergeStateStatus\":[[:space:]]*\"([^\"]+)\" ]]; then
          MS_STATE="${BASH_REMATCH[1]}"
        fi
        continue
      fi

      MONITOR_STDOUT=$(mock_pr_monitor)
      MONITOR_RC=$?
      while IFS='=' read -r KEY VALUE; do
        case "$KEY" in
          CI_STATUS) CI_STATUS="$VALUE" ;;
        esac
      done <<<"$MONITOR_STDOUT"
      if [ "$MONITOR_RC" -ne 0 ] || [ "$CI_STATUS" != "pass" ]; then
        STATUS="auto-rebase-blocked"
        REASON="auto-rebase-ci-${CI_STATUS:-monitor-failed}-iter$AUTO_REBASE_ITER"
        break
      fi

      MS_JSON=$(mock_gh_pr_view)
      MS_STATE=""
      if [[ "$MS_JSON" =~ \"mergeStateStatus\":[[:space:]]*\"([^\"]+)\" ]]; then
        MS_STATE="${BASH_REMATCH[1]}"
      fi

      case "$MS_STATE" in
        CLEAN|HAS_HOOKS|UNSTABLE) break ;;
        BEHIND) ;;
        BLOCKED|CONFLICTING)
          STATUS="auto-rebase-blocked"
          REASON="mergeStateStatus-$MS_STATE"
          break
          ;;
        UNKNOWN|"")
          STATUS="auto-rebase-blocked"
          REASON="auto-rebase-unknown"
          break
          ;;
        *)
          STATUS="auto-rebase-blocked"
          REASON="mergeStateStatus-$MS_STATE"
          break
          ;;
      esac
    done

    if [ -z "$STATUS" ] && [ "$MS_STATE" = "BEHIND" ] && [ "$AUTO_REBASE_ITER" -ge "$AUTO_REBASE_MAX" ]; then
      STATUS="behind-thrash"
      REASON="auto-rebase-exhausted"
    fi

    if [ -s "$REBASE_STDERR" ] \
       && { [ "$STATUS" = "behind-thrash" ] \
            || [ "$STATUS" = "auto-rebase-conflict" ] \
            || [ "$STATUS" = "auto-rebase-blocked" ]; }; then
      REBASE_STDERR_FILE="$REBASE_STDERR"
    else
      rm -f "$REBASE_STDERR"
    fi
  fi
}

# Helper: run a case with fresh queue + inputs, assert on output.
run_case() {
  local label="$1"
  reset_queues
  STATUS=""
  REASON=""
  CONFLICT_FILES_LIST=""
  REBASE_STDERR_FILE=""
}

# ===== Case 1: BEHIND on iter 1, CLEAN on iter 2 → loop breaks, no STATUS set
run_case "case1: BEHIND→CLEAN"
AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a BASE_BRANCH=main WORKTREE_PATH="$MOCKDIR" \
  STATUS="" REASON="" CONFLICT_FILES_LIST="" REBASE_STDERR_FILE=""
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'   # initial probe
queue_push "$FETCH_QUEUE"   0 ''
queue_push "$REBASE_QUEUE"  0 ''
queue_push "$PUSH_QUEUE"    0 ''
queue_push "$MONITOR_QUEUE" 0 'CI_STATUS=pass'
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"CLEAN"}'    # post-rebase recheck
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ -z "$STATUS" ]; then
  pass "[case1] BEHIND→CLEAN: loop broke, STATUS unset → Step 7 proceeds"
else
  fail "[case1] BEHIND→CLEAN" "expected empty STATUS, got '$STATUS' REASON='$REASON'"
fi

# ===== Case 2: BEHIND on all 3 iterations → STATUS=behind-thrash
run_case "case2: BEHIND×3 → behind-thrash"
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'   # initial
for i in 1 2 3; do
  queue_push "$FETCH_QUEUE"   0 ''
  queue_push "$REBASE_QUEUE"  0 ''
  queue_push "$PUSH_QUEUE"    0 ''
  queue_push "$MONITOR_QUEUE" 0 'CI_STATUS=pass'
  queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}' # post-rebase recheck stays BEHIND
done
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ "$STATUS" = "behind-thrash" ] && [ "$REASON" = "auto-rebase-exhausted" ]; then
  pass "[case2] BEHIND×3: STATUS=behind-thrash REASON=auto-rebase-exhausted"
else
  fail "[case2] BEHIND×3" "expected behind-thrash/auto-rebase-exhausted, got STATUS='$STATUS' REASON='$REASON'"
fi

# ===== Case 3: AUTO_FLAG=false → loop skipped entirely, no STATUS set
run_case "case3: AUTO_FLAG=false → skip"
# Queue would-be entries that should NOT be consumed.
queue_push "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=false; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ -z "$STATUS" ]; then
  pass "[case3] AUTO_FLAG=false: loop skipped, STATUS unset"
else
  fail "[case3] AUTO_FLAG=false" "expected empty STATUS, got '$STATUS'"
fi

# ===== Case 4: CI_STATUS=fail → loop skipped entirely
run_case "case4: CI=fail → skip"
queue_push "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=fail; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ -z "$STATUS" ]; then
  pass "[case4] CI=fail: loop skipped, STATUS unset"
else
  fail "[case4] CI=fail" "expected empty STATUS, got '$STATUS'"
fi

# ===== Case 5: Rebase conflict on iter 1 → STATUS=auto-rebase-conflict + CONFLICT_FILES_LIST
run_case "case5: rebase conflict"
queue_push "$GH_QUEUE"     0 '{"mergeStateStatus":"BEHIND"}'    # initial
queue_push "$FETCH_QUEUE"  0 ''
queue_push "$REBASE_QUEUE" 1 ''                                 # rebase fails → conflict
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ "$STATUS" = "auto-rebase-conflict" ]; then
  pass "[case5] rebase conflict: STATUS=auto-rebase-conflict"
else
  fail "[case5] rebase conflict STATUS" "expected auto-rebase-conflict, got '$STATUS'"
fi
if [ -n "$CONFLICT_FILES_LIST" ] && [ -s "$CONFLICT_FILES_LIST" ]; then
  pass "[case5] rebase conflict: CONFLICT_FILES_LIST sidecar populated"
else
  fail "[case5] CONFLICT_FILES_LIST" "expected sidecar path with conflict files, got '$CONFLICT_FILES_LIST'"
fi

# ===== Case 6: mergeStateStatus=BLOCKED → STATUS=auto-rebase-blocked
run_case "case6: BLOCKED post-rebase"
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'   # initial
queue_push "$FETCH_QUEUE"   0 ''
queue_push "$REBASE_QUEUE"  0 ''
queue_push "$PUSH_QUEUE"    0 ''
queue_push "$MONITOR_QUEUE" 0 'CI_STATUS=pass'
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"BLOCKED"}'  # post-rebase
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ "$STATUS" = "auto-rebase-blocked" ] && [ "$REASON" = "mergeStateStatus-BLOCKED" ]; then
  pass "[case6] BLOCKED post-rebase: STATUS=auto-rebase-blocked REASON=mergeStateStatus-BLOCKED"
else
  fail "[case6] BLOCKED" "expected auto-rebase-blocked/mergeStateStatus-BLOCKED, got STATUS='$STATUS' REASON='$REASON'"
fi

# ===== Case 7: mergeStateStatus=UNKNOWN → auto-rebase-unknown
run_case "case7: UNKNOWN post-rebase"
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'
queue_push "$FETCH_QUEUE"   0 ''
queue_push "$REBASE_QUEUE"  0 ''
queue_push "$PUSH_QUEUE"    0 ''
queue_push "$MONITOR_QUEUE" 0 'CI_STATUS=pass'
queue_push "$GH_QUEUE"      0 '{"mergeStateStatus":"UNKNOWN"}'
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ "$STATUS" = "auto-rebase-blocked" ] && [ "$REASON" = "auto-rebase-unknown" ]; then
  pass "[case7] UNKNOWN post-rebase: STATUS=auto-rebase-blocked REASON=auto-rebase-unknown"
else
  fail "[case7] UNKNOWN" "expected auto-rebase-blocked/auto-rebase-unknown, got STATUS='$STATUS' REASON='$REASON'"
fi

# ===== Case 8: Initial mergeStateStatus=CLEAN → loop never enters
run_case "case8: initial CLEAN → no-op"
queue_push "$GH_QUEUE" 0 '{"mergeStateStatus":"CLEAN"}'
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ -z "$STATUS" ]; then
  pass "[case8] initial CLEAN: loop never enters, STATUS unset"
else
  fail "[case8] initial CLEAN" "expected empty STATUS, got '$STATUS'"
fi

# ===== Case 9: PR_NUMBER empty → loop skipped (defensive)
run_case "case9: PR_NUMBER empty → skip"
STATUS=""; REASON=""; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=""; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
run_auto_rebase_block
if [ -z "$STATUS" ]; then
  pass "[case9] PR_NUMBER empty: loop skipped, STATUS unset"
else
  fail "[case9] PR_NUMBER empty" "expected empty STATUS, got '$STATUS'"
fi

# ===== Case 10: STATUS already set → loop skipped
run_case "case10: STATUS preset → skip"
STATUS="merge-failed"; REASON="prior-failure"; CONFLICT_FILES_LIST=""; REBASE_STDERR_FILE=""
AUTO_FLAG=true; CI_STATUS=pass; PR_NUMBER=1234; BRANCH=feat/a; BASE_BRANCH=main; WORKTREE_PATH="$MOCKDIR"
queue_push "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
run_auto_rebase_block
if [ "$STATUS" = "merge-failed" ]; then
  pass "[case10] STATUS=merge-failed preset: loop skipped, STATUS preserved"
else
  fail "[case10] STATUS preset" "expected merge-failed preserved, got '$STATUS'"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
