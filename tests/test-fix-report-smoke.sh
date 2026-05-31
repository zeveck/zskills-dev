#!/bin/bash
# Behavioral smoke for /fix-report's deterministic bash surface.
#
# Covers three executable surfaces of skills/fix-report/SKILL.md:
#   1. Worktree-gate exit-11: the preamble's ensure-worktree.sh integrity
#      check (`if [ ! -x "$HELPER" ]`) -> exit 11 + "run /update-zskills" msg.
#   2. The Step 6 `.landed`-status scan classification: the `for wt in
#      $(git worktree list ...)` loop + `case "$STATUS"` block. The scan
#      enumerates worktrees via `git worktree list`, so fixtures MUST be
#      REAL `git worktree add` worktrees in a `git init` sandbox, each
#      carrying a crafted `.landed`. Status vocabulary is the ACTUAL case
#      arms (full|landed, pr-ready, pr-ci-failing, pr-failed, conflict,
#      failed|direct-push-failed|direct-verify-failed, pr-state-unknown,
#      partial, *). There is NO `not-landed` arm; the ACTIVE classification
#      is the no-`.landed`-file `else` branch, not a status value.
#   3. PIPELINE_ID sanitization: the constructed FIX_REPORT_PIPELINE_ID is
#      routed through sanitize-pipeline-id.sh.
#
# All fixtures synthesized in mktemp -d; no network; no real gh.
#
# Run from repo root: bash tests/test-fix-report-smoke.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/fix-report/SKILL.md"
PASS_COUNT=0; FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== fix-report behavioral smoke ==="

# ── Surface 1: worktree-gate exit-11 ────────────────────────────────
# Extract the integrity-check fence from the preamble (self-contained
# enough to run with HELPER pointed at a nonexistent file).
GATE_BLOCK=$(awk '
  /HELPER="\$ZSKILLS_SKILLS_ROOT\/create-worktree\/scripts\/ensure-worktree.sh"/{capture=1}
  capture {print}
  capture && /exit 11/{found_exit=1}
  capture && found_exit && /^fi$/{exit}
' "$SKILL")

if [ -z "$GATE_BLOCK" ]; then
  fail "worktree-gate: could not extract integrity-check block" "awk extract empty"
else
  pass "worktree-gate: integrity-check block extracted from SKILL.md"
  # Run with a nonexistent HELPER. Strip the line that ASSIGNS HELPER from
  # the skill's $CLAUDE_PROJECT_DIR path (we override it ourselves).
  RUNNABLE=$(echo "$GATE_BLOCK" | grep -v '^HELPER=')
  # Run the gate in a subshell so its `exit 11` terminates only that
  # subshell; capture its exit code from the parent.
  OUT=$(
    HELPER="/nonexistent/path/ensure-worktree.sh"
    eval "$RUNNABLE" 2>&1
  )
  RC=$?
  OUT="${OUT}
RC=$RC"
  if echo "$OUT" | grep -q 'RC=11'; then
    pass "worktree-gate: missing helper -> exit 11"
  else
    fail "worktree-gate: missing helper did not exit 11" "got: $OUT"
  fi
  if echo "$OUT" | grep -q 'run /update-zskills to repair'; then
    pass "worktree-gate: actionable 'run /update-zskills to repair' message"
  else
    fail "worktree-gate: missing actionable repair message" "got: $OUT"
  fi
fi

# ── Surface 2: .landed-status scan classification ───────────────────
# Extract the Step 6 worktree-scan loop (the `for wt in` block through its
# matching `done`). It is self-contained: it shells out to `git worktree
# list` and reads `.landed` files, so we drive it inside a real git sandbox
# with REAL `git worktree add` worktrees.
SCAN_BLOCK=$(awk '
  /^for wt in \$\(git worktree list/{capture=1}
  capture {print}
  capture && /^done$/{exit}
' "$SKILL")

if [ -z "$SCAN_BLOCK" ]; then
  fail "landed-scan: could not extract scan loop" "awk extract empty"
else
  pass "landed-scan: scan loop extracted from SKILL.md"
  # Parity gate on the case-arm fingerprints so source drift fails the test.
  if echo "$SCAN_BLOCK" | grep -qF 'failed|direct-push-failed|direct-verify-failed)' \
     && echo "$SCAN_BLOCK" | grep -qF 'ACTIVE: $wt — no .landed marker'; then
    pass "landed-scan: case-arm + ACTIVE-else fingerprints present"
  else
    fail "landed-scan: fingerprint drift in scan block" "case arms changed"
  fi

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  (
    cd "$TMP" || exit 1
    git init -q -b main .
    git config user.email t@t.t; git config user.name t
    git commit -q --allow-empty -m base

    mk_wt() { # name status
      git worktree add -q -b "wt-$1" "$TMP/$1" main 2>/dev/null
      printf 'status: %s\n' "$2" > "$TMP/$1/.landed"
    }
    mk_wt safe-full full
    mk_wt safe-landed landed
    mk_wt safe-prready pr-ready
    mk_wt attn-cifail pr-ci-failing
    mk_wt attn-prfailed pr-failed
    mk_wt attn-conflict conflict
    mk_wt attn-unknownstate pr-state-unknown
    mk_wt failed-class failed
    mk_wt failed-directpush direct-push-failed
    mk_wt failed-directverify direct-verify-failed
    mk_wt partial-land partial
    mk_wt weird-status some-bogus-status
    # ACTIVE: a worktree with NO .landed marker.
    git worktree add -q -b wt-active "$TMP/active" main 2>/dev/null

    eval "$SCAN_BLOCK"
  ) > "$TMP/scan.out" 2>&1

  check_bucket() { # path-fragment expected-bucket label
    # Match the bucket word at line start (it may be followed by ":" or by
    # a parenthetical like "SAFE (worktree only):") on the line carrying
    # the worktree path.
    if grep -E "$1" "$TMP/scan.out" | grep -qE "^$2[ :(]"; then
      pass "landed-scan: $3"
    else
      fail "landed-scan: $3" "expected $2 for $1; out: $(grep "$1" "$TMP/scan.out" || echo none)"
    fi
  }
  check_bucket "/safe-full" "SAFE" "status full -> SAFE"
  check_bucket "/safe-landed" "SAFE" "status landed -> SAFE"
  check_bucket "/safe-prready" "SAFE" "status pr-ready -> SAFE (worktree only)"
  check_bucket "/attn-cifail" "NEEDS ATTENTION" "status pr-ci-failing -> NEEDS ATTENTION"
  check_bucket "/attn-prfailed" "NEEDS ATTENTION" "status pr-failed -> NEEDS ATTENTION"
  check_bucket "/attn-conflict" "NEEDS ATTENTION" "status conflict -> NEEDS ATTENTION"
  check_bucket "/attn-unknownstate" "NEEDS ATTENTION" "status pr-state-unknown -> NEEDS ATTENTION"
  check_bucket "/failed-class" "FAILED" "status failed -> FAILED"
  check_bucket "/failed-directpush" "FAILED" "status direct-push-failed -> FAILED"
  check_bucket "/failed-directverify" "FAILED" "status direct-verify-failed -> FAILED"
  check_bucket "/partial-land" "PARTIAL" "status partial -> PARTIAL"
  check_bucket "/weird-status" "UNKNOWN" "unrecognized status -> UNKNOWN catch-all"
  check_bucket "/active" "ACTIVE" "no .landed marker -> ACTIVE (else branch)"
fi

# ── Surface 3: PIPELINE_ID sanitization ─────────────────────────────
# The preamble constructs FIX_REPORT_PIPELINE_ID then routes it through
# sanitize-pipeline-id.sh. Drive the sanitizer (resolved via the install
# lane, same path the skill uses) with a dirty slug and assert it collapses
# to [a-zA-Z0-9._-].
SANITIZER="$REPO_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
if grep -qF 'bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$FIX_REPORT_PIPELINE_ID"' "$SKILL"; then
  pass "pipeline-id: SKILL.md routes FIX_REPORT_PIPELINE_ID through sanitize-pipeline-id.sh"
else
  fail "pipeline-id: SKILL.md no longer routes FIX_REPORT_PIPELINE_ID through sanitizer" "fingerprint drift"
fi
if [ -x "$SANITIZER" ]; then
  DIRTY='fix-report.2026 05/28:foo@bar baz'
  CLEAN=$(bash "$SANITIZER" "$DIRTY")
  if echo "$CLEAN" | grep -qE '^[a-zA-Z0-9._-]+$'; then
    pass "pipeline-id: dirty slug collapsed to [a-zA-Z0-9._-] ($CLEAN)"
  else
    fail "pipeline-id: sanitizer left invalid chars" "got: $CLEAN"
  fi
else
  fail "pipeline-id: sanitize-pipeline-id.sh not executable" "$SANITIZER missing"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
