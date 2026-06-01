#!/bin/bash
# tests/test-land-pr-drive-automerge.sh — regression tests for Issue #871.
#
# /land-pr Step 7d (`Drive a queued auto-merge to a terminal state`) closes
# the post-merge-request BEHIND stall. Step 7 requests GitHub auto-merge and
# returns; if a sibling PR lands *after* the request, our PR goes OPEN/BEHIND
# and (on "Require branches up to date" repos) the queued auto-merge waits
# indefinitely because it never auto-rebases. Step 7d drives the queued
# auto-merge to a terminus: it re-uses the EXACT Step 6b rebase machinery
# (gh poll → BEHIND-detect → fetch → rebase → push --force-with-lease →
# re-monitor) to clear post-request BEHIND, bounded by a wall-clock timeout
# AND a hard iteration cap so it can NEVER hang. Observed live on PR #856.
#
# EXTRACT-AND-RUN (SEAM_HARDENING_HIGH Phase 2): this NEW test extracts the
# real Step 7d ```bash fence out of skills/land-pr/SKILL.md via
# tests/lib/extract-fence.sh and RUNS it against PATH-shimmed
# gh/git/date/sleep + a shimmed pr-monitor.sh, with queue-driven outputs.
# Because Step 7d re-uses the Step-6b rebase sub-path inline, it carries the
# same hollow-green risk; mutating the production fence makes this suite FAIL.
#
# Terminal arms exercised (each maps to a distinct >&2 line in the fence):
#   1. MERGED reached                       → STATUS=merged, loop exits
#   2. BEHIND post-merge-request            → rebase + force-with-lease, then MERGED
#   3. UNKNOWN re-poll → MERGED             → bounded UNKNOWN resolver, not terminal
#   4. BLOCKED / CONFLICTING                → auto-rebase-blocked, surface + break
#   5. no-terminus-within-timeout           → PR left OPEN, REASON=auto-merge-wait-timeout
#   plus skip-guard (AUTO_FLAG/MERGE_REQUESTED/PR_STATE/STATUS) coverage.

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
for anchor in \
  'Step 7d — Drive a queued auto-merge to a terminal state (Issue #871)' \
  'TW_ITER_MAX=10' \
  'TW_PR_STATE" = "MERGED' \
  'push --force-with-lease origin "$BRANCH"' \
  'mergeStateStatus-$TW_MS_STATE' \
  'auto-merge-wait-timeout' \
  'AUTO_REBASE_MAX' \
  'CLEAN|HAS_HOOKS|UNSTABLE' \
  'BLOCKED|CONFLICTING'
do
  if ! grep -qF "$anchor" "$SKILL_FILE"; then
    fail "[anchor] SKILL.md missing Step 7d anchor: $anchor" "(Issue #871 regression)"
  else
    pass "[anchor] SKILL.md contains Step 7d anchor: $anchor"
  fi
done

# ---- Extract the REAL Step 7d fence from production SKILL.md ---------
FIXTURE=$(mktemp -d "/tmp/land-pr-drive-automerge-test.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

STEP7D_FENCE="$FIXTURE/step7d.sh"
if ! extract_fence_between "$SKILL_FILE" \
      'Step 7d — Drive a queued auto-merge to a terminal state' \
      'Step 7b — Fast-forward local main' 1 0 > "$STEP7D_FENCE"; then
  echo "FAIL: could not extract Step 7d fence from $SKILL_FILE" >&2
  exit 1
fi
# Sanity: extracted fence carries production landmarks.
if ! grep -qF 'TW_ITER_MAX=10' "$STEP7D_FENCE" \
   || ! grep -qF 'auto-merge-wait-timeout' "$STEP7D_FENCE" \
   || ! grep -qF 'push --force-with-lease origin "$BRANCH"' "$STEP7D_FENCE"; then
  echo "FAIL: extracted Step 7d fence missing production landmarks" >&2
  exit 1
fi
pass "[extract] Step 7d production fence extracted from SKILL.md"

STEP7D_RUN="$FIXTURE/step7d-run.sh"
patch_caller_loop "$STEP7D_FENCE" "$STEP7D_RUN"

# ---- Queue-driven PATH shims ----------------------------------------
SHIM_BIN="$FIXTURE/bin"
SKILLS_ROOT="$FIXTURE/skills-root"
mkdir -p "$SHIM_BIN" "$SKILLS_ROOT/land-pr/scripts"

GH_QUEUE="$FIXTURE/gh.queue"
REBASE_QUEUE="$FIXTURE/rebase.queue"
PUSH_QUEUE="$FIXTURE/push.queue"
FETCH_QUEUE="$FIXTURE/fetch.queue"
MONITOR_QUEUE="$FIXTURE/monitor.queue"
DATE_FILE="$FIXTURE/date.now"   # monotonic fake clock (seconds since fixture epoch)

# gh shim: pops GH_QUEUE for `pr view ... --json state,mergeStateStatus`.
cat > "$SHIM_BIN/gh" <<EOF
#!/usr/bin/env bash
Q="$GH_QUEUE"
if [ -s "\$Q" ]; then
  line=\$(head -n1 "\$Q"); tail -n +2 "\$Q" > "\$Q.t" && mv "\$Q.t" "\$Q"
  printf '%s' "\${line#*|}"
  exit "\${line%%|*}"
fi
printf '{"state":"OPEN","mergeStateStatus":"UNKNOWN"}'
exit 0
EOF
chmod +x "$SHIM_BIN/gh"

# git shim (same shape as the Step 6b test).
cat > "$SHIM_BIN/git" <<EOF
#!/usr/bin/env bash
FETCH_Q="$FETCH_QUEUE"; REBASE_Q="$REBASE_QUEUE"; PUSH_Q="$PUSH_QUEUE"
if [ "\${1:-}" = "-C" ]; then shift 2; fi
pop() { local q="\$1"; if [ -s "\$q" ]; then local l; l=\$(head -n1 "\$q"); tail -n +2 "\$q" > "\$q.t" && mv "\$q.t" "\$q"; echo "\${l%%|*}"; return; fi; echo 0; }
case "\${1:-}" in
  fetch)  exit "\$(pop "\$FETCH_Q")" ;;
  rebase) [ "\${2:-}" = "--abort" ] && exit 0; exit "\$(pop "\$REBASE_Q")" ;;
  push)   exit "\$(pop "\$PUSH_Q")" ;;
  diff)   echo "conflict-file.txt"; exit 0 ;;
  *)      exit 0 ;;
esac
EOF
chmod +x "$SHIM_BIN/git"

# pr-monitor.sh shim.
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

# date shim: `date +%s` reads a fake monotonic clock and post-increments it
# by 1 each call, so the wall-clock loop condition advances deterministically
# (no real wall-clock dependence). Any non-"+%s" usage falls through to real.
cat > "$SHIM_BIN/date" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "+%s" ]; then
  F="$DATE_FILE"
  n=0; [ -s "\$F" ] && n=\$(cat "\$F")
  echo "\$n"
  echo "\$((n + 1))" > "\$F"
  exit 0
fi
exec /usr/bin/env -i PATH=/usr/bin:/bin date "\$@"
EOF
chmod +x "$SHIM_BIN/date"

# sleep shim → no-op.
printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM_BIN/sleep"
chmod +x "$SHIM_BIN/sleep"

qpush() { printf '%s|%s\n' "$2" "$3" >> "$1"; }
reset_queues() {
  : > "$GH_QUEUE"; : > "$REBASE_QUEUE"; : > "$PUSH_QUEUE"; : > "$FETCH_QUEUE"; : > "$MONITOR_QUEUE"
  echo 0 > "$DATE_FILE"
}

# run_real_7d — run the EXTRACTED production Step 7d fence in a clean subshell.
# Echoes resulting STATUS/REASON/PR_STATE as key=value lines on stdout, and
# the fence's own >&2 INFO/WARN lines pass through to the caller's captured
# stderr (so cases can assert on them).
run_real_7d() {
  (
    set +e
    set -u
    export PATH="$SHIM_BIN:$PATH"
    export ZSKILLS_SKILLS_ROOT="$SKILLS_ROOT"
    export CLAUDE_PROJECT_DIR="$REPO_ROOT"
    seed_caller_loop_inputs
    CONFLICT_FILES_LIST=""
    # shellcheck disable=SC1090
    . "$STEP7D_RUN"
    printf 'STATUS=%s\n' "${STATUS:-}"
    printf 'REASON=%s\n' "${REASON:-}"
    printf 'PR_STATE=%s\n' "${PR_STATE:-}"
  )
}

parse_out() {
  out_STATUS=""; out_REASON=""; out_PR_STATE=""
  while IFS='=' read -r k v; do
    case "$k" in
      STATUS) out_STATUS="$v" ;;
      REASON) out_REASON="$v" ;;
      PR_STATE) out_PR_STATE="$v" ;;
    esac
  done <<<"$1"
}

# ===== Case 1: queued auto-merge fires → MERGED on first poll ==========
reset_queues
qpush "$GH_QUEUE" 0 '{"state":"MERGED","mergeStateStatus":"CLEAN"}'
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>"$FIXTURE/err1" )
parse_out "$blob"
if [ "$out_STATUS" = "merged" ] && [ "$out_PR_STATE" = "MERGED" ]; then
  pass "[case1] MERGED on first poll: STATUS=merged PR_STATE=MERGED"
else
  fail "[case1] MERGED reached" "STATUS='$out_STATUS' PR_STATE='$out_PR_STATE' REASON='$out_REASON'"
fi
if grep -qF "reached MERGED" "$FIXTURE/err1"; then
  pass "[case1] INFO log emitted (reached MERGED)"
else
  fail "[case1] INFO log" "err: $(cat "$FIXTURE/err1")"
fi

# ===== Case 2: BEHIND post-merge-request → rebase + force-with-lease, then MERGED
reset_queues
# iter1: BEHIND → enter inline rebase machinery (fetch/rebase/push/monitor),
# clears, loop back. iter2: MERGED.
qpush "$GH_QUEUE"      0 '{"state":"OPEN","mergeStateStatus":"BEHIND"}'
qpush "$FETCH_QUEUE"   0 ''
qpush "$REBASE_QUEUE"  0 ''
qpush "$PUSH_QUEUE"    0 ''
qpush "$MONITOR_QUEUE" 0 'pass'
qpush "$GH_QUEUE"      0 '{"state":"MERGED","mergeStateStatus":"CLEAN"}'
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>"$FIXTURE/err2" )
parse_out "$blob"
if [ "$out_STATUS" = "merged" ] && [ "$out_PR_STATE" = "MERGED" ] && [ ! -s "$REBASE_QUEUE" ]; then
  pass "[case2] BEHIND post-request: rebase fired (queue drained) then MERGED"
else
  fail "[case2] BEHIND post-request" "STATUS='$out_STATUS' PR_STATE='$out_PR_STATE' rebase-left='$(cat "$REBASE_QUEUE")'"
fi
if grep -qF "went BEHIND post-merge-request" "$FIXTURE/err2"; then
  pass "[case2] INFO log emitted (went BEHIND post-merge-request)"
else
  fail "[case2] INFO log" "err: $(cat "$FIXTURE/err2")"
fi

# ===== Case 2b: BEHIND rebase push fails on final iter → auto-rebase-blocked
reset_queues
qpush "$GH_QUEUE" 0 '{"state":"OPEN","mergeStateStatus":"BEHIND"}'
for i in 1 2 3; do
  qpush "$FETCH_QUEUE" 0 ''
  qpush "$REBASE_QUEUE" 0 ''
  qpush "$PUSH_QUEUE"  1 ''   # push fails every iter → exhausts at iter 3
done
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>"$FIXTURE/err2b" )
parse_out "$blob"
if [ "$out_STATUS" = "auto-rebase-blocked" ]; then
  pass "[case2b] BEHIND rebase push exhausted: STATUS=auto-rebase-blocked"
else
  fail "[case2b] push exhausted" "STATUS='$out_STATUS' REASON='$out_REASON'"
fi

# ===== Case 3: UNKNOWN re-poll then MERGED → bounded resolver, not terminal
reset_queues
qpush "$GH_QUEUE" 0 '{"state":"OPEN","mergeStateStatus":"UNKNOWN"}'  # iter1 poll → UNKNOWN
qpush "$GH_QUEUE" 0 '{"state":"OPEN","mergeStateStatus":"UNKNOWN"}'  # re-poll 1 still UNKNOWN
qpush "$GH_QUEUE" 0 '{"state":"MERGED","mergeStateStatus":"CLEAN"}'  # re-poll 2 → MERGED
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>"$FIXTURE/err3" )
parse_out "$blob"
if [ "$out_STATUS" = "merged" ] && [ "$out_PR_STATE" = "MERGED" ]; then
  pass "[case3] UNKNOWN re-poll resolves to MERGED (UNKNOWN not treated terminal)"
else
  fail "[case3] UNKNOWN re-poll" "STATUS='$out_STATUS' PR_STATE='$out_PR_STATE' REASON='$out_REASON'"
fi

# ===== Case 4: BLOCKED → auto-rebase-blocked, surface + break ==========
reset_queues
qpush "$GH_QUEUE" 0 '{"state":"OPEN","mergeStateStatus":"BLOCKED"}'
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>"$FIXTURE/err4" )
parse_out "$blob"
if [ "$out_STATUS" = "auto-rebase-blocked" ] && [ "$out_REASON" = "mergeStateStatus-BLOCKED" ]; then
  pass "[case4] BLOCKED: STATUS=auto-rebase-blocked REASON=mergeStateStatus-BLOCKED"
else
  fail "[case4] BLOCKED" "STATUS='$out_STATUS' REASON='$out_REASON'"
fi
if grep -qF "surfacing" "$FIXTURE/err4"; then
  pass "[case4] WARN log emitted (surfacing)"
else
  fail "[case4] WARN log" "err: $(cat "$FIXTURE/err4")"
fi

# ===== Case 4b: CONFLICTING → auto-rebase-blocked ======================
reset_queues
qpush "$GH_QUEUE" 0 '{"state":"OPEN","mergeStateStatus":"CONFLICTING"}'
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>/dev/null )
parse_out "$blob"
if [ "$out_STATUS" = "auto-rebase-blocked" ] && [ "$out_REASON" = "mergeStateStatus-CONFLICTING" ]; then
  pass "[case4b] CONFLICTING: STATUS=auto-rebase-blocked REASON=mergeStateStatus-CONFLICTING"
else
  fail "[case4b] CONFLICTING" "STATUS='$out_STATUS' REASON='$out_REASON'"
fi

# ===== Case 5: waited (CLEAN) then timed out → PR OPEN, wait-timeout REASON
# CLEAN means mergeable+queued → keep waiting. With CI_TIMEOUT=2 and the
# fake clock advancing 1s per `date +%s` call, the wall-clock deadline is
# hit after a couple of poll iterations while still OPEN.
reset_queues
for i in 1 2 3 4 5; do
  qpush "$GH_QUEUE" 0 '{"state":"OPEN","mergeStateStatus":"CLEAN"}'
done
blob=$( AUTO_FLAG=true MERGE_REQUESTED=true PR_STATE=OPEN NO_MONITOR=false \
        PR_RESUME="" PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
        WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=2 run_real_7d 2>"$FIXTURE/err5" )
parse_out "$blob"
if [ "$out_PR_STATE" = "OPEN" ] && [ "$out_REASON" = "auto-merge-wait-timeout" ] \
   && [ "$out_STATUS" != "merged" ]; then
  pass "[case5] no terminus within timeout: PR left OPEN, REASON=auto-merge-wait-timeout"
else
  fail "[case5] wait-timeout" "STATUS='$out_STATUS' PR_STATE='$out_PR_STATE' REASON='$out_REASON'"
fi
if grep -qF "did not reach a terminus" "$FIXTURE/err5"; then
  pass "[case5] WARN log emitted (did not reach a terminus)"
else
  fail "[case5] WARN log" "err: $(cat "$FIXTURE/err5")"
fi

# ===== Case 6: skip-guards (run conditions) ============================
# Each of these must skip Step 7d entirely (no gh poll, STATUS untouched).
# Inputs are passed as "VAR=val" tokens which the subshell exports before
# calling run_real_7d (a shell function — so we cannot front it with `env`).
skip_guard() {
  local label="$1"; shift
  reset_queues
  qpush "$GH_QUEUE" 0 '{"state":"MERGED","mergeStateStatus":"CLEAN"}'  # would-fire if entered
  blob=$(
    for kv in "$@"; do export "${kv?}"; done
    PR_NUMBER=856 BRANCH=feat/a BASE_BRANCH=main \
      WORKTREE_PATH="$FIXTURE" CI_TIMEOUT=600 run_real_7d 2>/dev/null
  )
  parse_out "$blob"
  # Entered-and-merged would set STATUS=merged; a proper skip leaves the
  # gh queue unconsumed.
  if [ "$out_STATUS" != "merged" ] && [ -s "$GH_QUEUE" ]; then
    pass "[case6/$label] Step 7d skipped (gh queue untouched, STATUS not flipped to merged)"
  else
    fail "[case6/$label] expected skip" "STATUS='$out_STATUS' gh-left='$(cat "$GH_QUEUE")'"
  fi
}
skip_guard "auto-flag-false"   AUTO_FLAG=false MERGE_REQUESTED=true  PR_STATE=OPEN   NO_MONITOR=false PR_RESUME=""
skip_guard "merge-not-req"     AUTO_FLAG=true  MERGE_REQUESTED=false PR_STATE=OPEN   NO_MONITOR=false PR_RESUME=""
skip_guard "pr-state-merged"   AUTO_FLAG=true  MERGE_REQUESTED=true  PR_STATE=MERGED NO_MONITOR=false PR_RESUME=""
skip_guard "no-monitor"        AUTO_FLAG=true  MERGE_REQUESTED=true  PR_STATE=OPEN   NO_MONITOR=true  PR_RESUME=""
skip_guard "pr-resume"         AUTO_FLAG=true  MERGE_REQUESTED=true  PR_STATE=OPEN   NO_MONITOR=false PR_RESUME="42"
skip_guard "status-merge-fail" AUTO_FLAG=true  MERGE_REQUESTED=true  PR_STATE=OPEN   NO_MONITOR=false PR_RESUME="" STATUS=merge-failed

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
