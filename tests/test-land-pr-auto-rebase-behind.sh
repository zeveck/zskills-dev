#!/bin/bash
# tests/test-land-pr-auto-rebase-behind.sh — regression tests for Issue #266
# (+ the #875 UNKNOWN→definite re-poll prelude).
#
# /land-pr Step 6b (`Auto-rebase BEHIND PRs post-CI-green`) closes the
# OPEN/BEHIND auto-merge stall gap. Without it, when a sibling PR lands
# between `pr-monitor.sh` returning CI=pass and `pr-merge.sh` requesting
# auto-merge, the feature branch goes BEHIND, GitHub's auto-merge waits
# indefinitely (on repos with "Require branches to be up to date" branch
# protection), and the orchestrator must manually rebase + force-push.
#
# EXTRACT-AND-RUN (SEAM_HARDENING_HIGH Phase 2): this test no longer carries
# a re-implemented copy of the Step 6b control flow. It EXTRACTS the real
# Step 6b ```bash fence (and the Step 7 merge-gate fence that follows the
# same step) out of skills/land-pr/SKILL.md via tests/lib/extract-fence.sh
# and RUNS them against PATH-shimmed gh/git/pr-monitor.sh/sleep with
# queue-driven outputs. Mutating the production fence (e.g. flipping the
# BEHIND comparison, dropping the UNKNOWN re-poll, or changing a STATUS
# token) makes this suite FAIL — that is the point: the test exercises
# production code, not a copy.
#
# Two layers:
#   1. Anchor/schema/mapping greps — sentinel strings + the Step 8 status
#      mapping that MUST survive future edits (Issue #266 regression guard).
#   2. Extract-and-run behavior cases — drive the REAL fence with queued
#      gh/monitor/git outcomes and assert the resulting STATUS/REASON.
#
# Cases (the 10 preserved + the new #875 re-poll):
#   1.  BEHIND→CLEAN              (single rebase, clears, STATUS unset)
#   2.  BEHIND×3 → behind-thrash  (loop cap, auto-rebase-exhausted)
#   3.  AUTO_FLAG=false           skip-guard
#   4.  CI_STATUS!=pass           skip-guard
#   5.  rebase conflict           → auto-rebase-conflict + sidecar
#   6.  BLOCKED post-rebase       → auto-rebase-blocked / mergeStateStatus-BLOCKED
#   7.  UNKNOWN post-rebase       → auto-rebase-blocked / auto-rebase-unknown
#   8.  initial CLEAN             no-op (loop never enters)
#   9.  PR_NUMBER empty           skip-guard
#   10. STATUS preset             skip-guard
#   11. NEW (#875): UNKNOWN-then-BEHIND initial re-poll resolves to BEHIND
#       and the rebase fires (not a silent no-op).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/land-pr/SKILL.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"
# shellcheck source=tests/lib/landpr-harness.sh
. "$SCRIPT_DIR/lib/landpr-harness.sh"

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
  'BLOCKED|CONFLICTING' \
  'UNKNOWN_POLL_MAX=5'
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

# ---- Extract the REAL Step 6b fence from production SKILL.md ---------
FIXTURE=$(mktemp -d "/tmp/land-pr-auto-rebase-test.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

STEP6B_FENCE="$FIXTURE/step6b.sh"
if ! extract_fence_between "$SKILL_FILE" \
      'Step 6b — Auto-rebase BEHIND PRs post-CI-green' \
      'Step 7 — Merge' 1 0 > "$STEP6B_FENCE"; then
  echo "FAIL: could not extract Step 6b fence from $SKILL_FILE" >&2
  exit 1
fi
# Sanity: the extracted fence is the real one (carries production landmarks).
if ! grep -qF 'push --force-with-lease origin "$BRANCH"' "$STEP6B_FENCE" \
   || ! grep -qF 'UNKNOWN_POLL_MAX=5' "$STEP6B_FENCE"; then
  echo "FAIL: extracted Step 6b fence missing production landmarks" >&2
  exit 1
fi
pass "[extract] Step 6b production fence extracted from SKILL.md"

# Patch out the config source (we set ZSKILLS_SKILLS_ROOT ourselves).
STEP6B_RUN="$FIXTURE/step6b-run.sh"
patch_caller_loop "$STEP6B_FENCE" "$STEP6B_RUN"

# ---- Queue-driven PATH shims for gh / git / pr-monitor.sh / sleep ----
# The fence calls (mid-block): `gh pr view ... --json mergeStateStatus`,
# `git -C <dir> fetch|rebase|push|diff|rebase --abort`,
# `bash "$ZSKILLS_SKILLS_ROOT/land-pr/scripts/pr-monitor.sh" ...`, and
# `sleep`. Each external is a thin shim that pops a predetermined
# rc|payload line off a per-command queue file.
SHIM_BIN="$FIXTURE/bin"
SKILLS_ROOT="$FIXTURE/skills-root"
mkdir -p "$SHIM_BIN" "$SKILLS_ROOT/land-pr/scripts"

GH_QUEUE="$FIXTURE/gh.queue"
REBASE_QUEUE="$FIXTURE/rebase.queue"
PUSH_QUEUE="$FIXTURE/push.queue"
FETCH_QUEUE="$FIXTURE/fetch.queue"
MONITOR_QUEUE="$FIXTURE/monitor.queue"

# gh shim: pops GH_QUEUE for `pr view ... --json mergeStateStatus`.
cat > "$SHIM_BIN/gh" <<EOF
#!/usr/bin/env bash
Q="$GH_QUEUE"
if [ -s "\$Q" ]; then
  line=\$(head -n1 "\$Q"); tail -n +2 "\$Q" > "\$Q.t" && mv "\$Q.t" "\$Q"
  printf '%s' "\${line#*|}"
  exit "\${line%%|*}"
fi
printf '{"mergeStateStatus":"UNKNOWN"}'
exit 0
EOF
chmod +x "$SHIM_BIN/gh"

# git shim: dispatch on the verb (after stripping a leading -C <dir>).
cat > "$SHIM_BIN/git" <<EOF
#!/usr/bin/env bash
FETCH_Q="$FETCH_QUEUE"; REBASE_Q="$REBASE_QUEUE"; PUSH_Q="$PUSH_QUEUE"
if [ "\${1:-}" = "-C" ]; then shift 2; fi
pop() { # \$1=queue → echoes rc, consuming head; default rc 0
  local q="\$1"
  if [ -s "\$q" ]; then
    local line; line=\$(head -n1 "\$q"); tail -n +2 "\$q" > "\$q.t" && mv "\$q.t" "\$q"
    echo "\${line%%|*}"; return
  fi
  echo 0
}
case "\${1:-}" in
  fetch)  exit "\$(pop "\$FETCH_Q")" ;;
  rebase)
    if [ "\${2:-}" = "--abort" ]; then exit 0; fi
    exit "\$(pop "\$REBASE_Q")" ;;
  push)   exit "\$(pop "\$PUSH_Q")" ;;
  diff)   echo "conflict-file.txt"; exit 0 ;;
  *)      exit 0 ;;
esac
EOF
chmod +x "$SHIM_BIN/git"

# pr-monitor.sh shim (invoked via \$ZSKILLS_SKILLS_ROOT/land-pr/scripts/...):
# pops MONITOR_QUEUE and emits CI_STATUS=<payload> on stdout, rc from queue.
cat > "$SKILLS_ROOT/land-pr/scripts/pr-monitor.sh" <<EOF
#!/usr/bin/env bash
Q="$MONITOR_QUEUE"
if [ -s "\$Q" ]; then
  line=\$(head -n1 "\$Q"); tail -n +2 "\$Q" > "\$Q.t" && mv "\$Q.t" "\$Q"
  printf 'CI_STATUS=%s\n' "\${line#*|}"
  exit "\${line%%|*}"
fi
printf 'CI_STATUS=pass\n'
exit 0
EOF
chmod +x "$SKILLS_ROOT/land-pr/scripts/pr-monitor.sh"

# sleep shim → no-op so the UNKNOWN re-poll runs fast.
cat > "$SHIM_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SHIM_BIN/sleep"

qpush() { printf '%s|%s\n' "$2" "$3" >> "$1"; }
reset_queues() { : > "$GH_QUEUE"; : > "$REBASE_QUEUE"; : > "$PUSH_QUEUE"; : > "$FETCH_QUEUE"; : > "$MONITOR_QUEUE"; }

# run_real_6b — run the EXTRACTED production fence in a clean subshell with
# the input-prelude seeded + per-case overrides exported by the caller.
# Echoes the resulting STATUS/REASON/CONFLICT_FILES_LIST as key=value lines.
run_real_6b() {
  (
    set +e
    set -u
    export PATH="$SHIM_BIN:$PATH"
    export ZSKILLS_SKILLS_ROOT="$SKILLS_ROOT"
    export CLAUDE_PROJECT_DIR="$REPO_ROOT"
    seed_caller_loop_inputs
    CONFLICT_FILES_LIST=""
    # shellcheck disable=SC1090
    . "$STEP6B_RUN"
    printf 'STATUS=%s\n' "${STATUS:-}"
    printf 'REASON=%s\n' "${REASON:-}"
    printf 'CONFLICT_FILES_LIST=%s\n' "${CONFLICT_FILES_LIST:-}"
    printf 'REBASE_STDERR_FILE=%s\n' "${REBASE_STDERR_FILE:-}"
  )
}

# Parse a key=value blob into out_STATUS/out_REASON/...
parse_out() {
  out_STATUS=""; out_REASON=""; out_CONFLICT=""; out_STDERR=""
  while IFS='=' read -r k v; do
    case "$k" in
      STATUS) out_STATUS="$v" ;;
      REASON) out_REASON="$v" ;;
      CONFLICT_FILES_LIST) out_CONFLICT="$v" ;;
      REBASE_STDERR_FILE) out_STDERR="$v" ;;
    esac
  done <<<"$1"
}

# ===== Case 1: BEHIND on iter 1, CLEAN on iter 2 → loop breaks, no STATUS
reset_queues
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'
qpush "$FETCH_QUEUE"   0 ''
qpush "$REBASE_QUEUE"  0 ''
qpush "$PUSH_QUEUE"    0 ''
qpush "$MONITOR_QUEUE" 0 'pass'
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"CLEAN"}'
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ -z "$out_STATUS" ]; then
  pass "[case1] BEHIND→CLEAN: loop broke, STATUS unset → Step 7 proceeds"
else
  fail "[case1] BEHIND→CLEAN" "expected empty STATUS, got '$out_STATUS' REASON='$out_REASON'"
fi

# ===== Case 2: BEHIND on all 3 iterations → STATUS=behind-thrash
reset_queues
qpush "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
for i in 1 2 3; do
  qpush "$FETCH_QUEUE"   0 ''
  qpush "$REBASE_QUEUE"  0 ''
  qpush "$PUSH_QUEUE"    0 ''
  qpush "$MONITOR_QUEUE" 0 'pass'
  qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'
done
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ "$out_STATUS" = "behind-thrash" ] && [ "$out_REASON" = "auto-rebase-exhausted" ]; then
  pass "[case2] BEHIND×3: STATUS=behind-thrash REASON=auto-rebase-exhausted"
else
  fail "[case2] BEHIND×3" "expected behind-thrash/auto-rebase-exhausted, got STATUS='$out_STATUS' REASON='$out_REASON'"
fi

# ===== Case 3: AUTO_FLAG=false → loop skipped entirely, no STATUS set
reset_queues
qpush "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
parse_out "$( AUTO_FLAG=false CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ -z "$out_STATUS" ]; then
  pass "[case3] AUTO_FLAG=false: loop skipped, STATUS unset"
else
  fail "[case3] AUTO_FLAG=false" "expected empty STATUS, got '$out_STATUS'"
fi

# ===== Case 4: CI_STATUS=fail → loop skipped entirely
reset_queues
qpush "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
parse_out "$( AUTO_FLAG=true CI_STATUS=fail PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ -z "$out_STATUS" ]; then
  pass "[case4] CI=fail: loop skipped, STATUS unset"
else
  fail "[case4] CI=fail" "expected empty STATUS, got '$out_STATUS'"
fi

# ===== Case 5: Rebase conflict on iter 1 → auto-rebase-conflict + sidecar
reset_queues
qpush "$GH_QUEUE"     0 '{"mergeStateStatus":"BEHIND"}'
qpush "$FETCH_QUEUE"  0 ''
qpush "$REBASE_QUEUE" 1 ''
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ "$out_STATUS" = "auto-rebase-conflict" ]; then
  pass "[case5] rebase conflict: STATUS=auto-rebase-conflict"
else
  fail "[case5] rebase conflict STATUS" "expected auto-rebase-conflict, got '$out_STATUS'"
fi
if [ -n "$out_CONFLICT" ] && [ -s "$out_CONFLICT" ]; then
  pass "[case5] rebase conflict: CONFLICT_FILES_LIST sidecar populated"
else
  fail "[case5] CONFLICT_FILES_LIST" "expected sidecar path with conflict files, got '$out_CONFLICT'"
fi

# ===== Case 6: mergeStateStatus=BLOCKED → auto-rebase-blocked
reset_queues
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'
qpush "$FETCH_QUEUE"   0 ''
qpush "$REBASE_QUEUE"  0 ''
qpush "$PUSH_QUEUE"    0 ''
qpush "$MONITOR_QUEUE" 0 'pass'
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"BLOCKED"}'
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ "$out_STATUS" = "auto-rebase-blocked" ] && [ "$out_REASON" = "mergeStateStatus-BLOCKED" ]; then
  pass "[case6] BLOCKED post-rebase: STATUS=auto-rebase-blocked REASON=mergeStateStatus-BLOCKED"
else
  fail "[case6] BLOCKED" "expected auto-rebase-blocked/mergeStateStatus-BLOCKED, got STATUS='$out_STATUS' REASON='$out_REASON'"
fi

# ===== Case 7: mergeStateStatus=UNKNOWN (post-rebase, terminal) → auto-rebase-unknown
# The post-rebase re-check is NOT re-polled (only the INITIAL probe re-polls
# per #875); a UNKNOWN at the post-rebase recheck terminates the loop.
reset_queues
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'
qpush "$FETCH_QUEUE"   0 ''
qpush "$REBASE_QUEUE"  0 ''
qpush "$PUSH_QUEUE"    0 ''
qpush "$MONITOR_QUEUE" 0 'pass'
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"UNKNOWN"}'
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ "$out_STATUS" = "auto-rebase-blocked" ] && [ "$out_REASON" = "auto-rebase-unknown" ]; then
  pass "[case7] UNKNOWN post-rebase: STATUS=auto-rebase-blocked REASON=auto-rebase-unknown"
else
  fail "[case7] UNKNOWN" "expected auto-rebase-blocked/auto-rebase-unknown, got STATUS='$out_STATUS' REASON='$out_REASON'"
fi

# ===== Case 8: Initial mergeStateStatus=CLEAN → loop never enters
reset_queues
qpush "$GH_QUEUE" 0 '{"mergeStateStatus":"CLEAN"}'
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ -z "$out_STATUS" ]; then
  pass "[case8] initial CLEAN: loop never enters, STATUS unset"
else
  fail "[case8] initial CLEAN" "expected empty STATUS, got '$out_STATUS'"
fi

# ===== Case 9: PR_NUMBER empty → loop skipped (defensive)
reset_queues
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER="" BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ -z "$out_STATUS" ]; then
  pass "[case9] PR_NUMBER empty: loop skipped, STATUS unset"
else
  fail "[case9] PR_NUMBER empty" "expected empty STATUS, got '$out_STATUS'"
fi

# ===== Case 10: STATUS already set → loop skipped
reset_queues
qpush "$GH_QUEUE" 0 '{"mergeStateStatus":"BEHIND"}'
parse_out "$( STATUS="merge-failed" REASON="prior-failure" AUTO_FLAG=true \
              CI_STATUS=pass PR_NUMBER=1234 BRANCH=feat/a BASE_BRANCH=main \
              WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ "$out_STATUS" = "merge-failed" ]; then
  pass "[case10] STATUS=merge-failed preset: loop skipped, STATUS preserved"
else
  fail "[case10] STATUS preset" "expected merge-failed preserved, got '$out_STATUS'"
fi

# ===== Case 11 (#875): UNKNOWN-then-BEHIND initial re-poll → rebase fires ====
# The first `gh pr view` returns UNKNOWN; the bounded re-poll prelude probes
# again and gets BEHIND, so the BEHIND loop MUST enter and the rebase fires
# (closing the live hollow-green where UNKNOWN→blocked silently no-op'd a PR
# that was actually BEHIND). We prove the rebase fired by consuming the
# fetch/rebase/push/monitor queue entries and reaching CLEAN with STATUS unset.
reset_queues
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"UNKNOWN"}'   # initial probe → triggers re-poll
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"BEHIND"}'    # re-poll resolves to BEHIND
qpush "$FETCH_QUEUE"   0 ''
qpush "$REBASE_QUEUE"  0 ''
qpush "$PUSH_QUEUE"    0 ''
qpush "$MONITOR_QUEUE" 0 'pass'
qpush "$GH_QUEUE"      0 '{"mergeStateStatus":"CLEAN"}'     # post-rebase recheck clears
# Sentinel: if the rebase fired, the REBASE_QUEUE is fully drained.
parse_out "$( AUTO_FLAG=true CI_STATUS=pass PR_NUMBER=856 BRANCH=feat/a \
              BASE_BRANCH=main WORKTREE_PATH="$FIXTURE" run_real_6b )"
if [ -z "$out_STATUS" ] && [ ! -s "$REBASE_QUEUE" ]; then
  pass "[case11] UNKNOWN→BEHIND re-poll: rebase fired (queue drained), STATUS unset"
else
  fail "[case11] UNKNOWN re-poll" "expected rebase to fire (drained REBASE_QUEUE, STATUS unset); got STATUS='$out_STATUS' rebase-left='$(cat "$REBASE_QUEUE")'"
fi

# Negative control: a pre-#875 implementation would map the initial UNKNOWN
# straight to auto-rebase-blocked and NEVER touch the rebase queue. Assert the
# fence did NOT do that.
if [ "$out_STATUS" = "auto-rebase-blocked" ]; then
  fail "[case11-neg] UNKNOWN initial mapped to blocked (the #875 hollow-green)" "STATUS='$out_STATUS' REASON='$out_REASON'"
else
  pass "[case11-neg] initial UNKNOWN NOT short-circuited to auto-rebase-blocked (re-poll honored)"
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
