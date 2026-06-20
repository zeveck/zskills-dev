#!/bin/bash
# tests/test-commit-pr-caller-loop.sh — extract-and-run the REAL /commit pr
# canonical /land-pr caller loop.
#
# SEAM_HARDENING_HIGH Phase 3. Supersedes the static-grep coverage that used
# to live in tests/test-commit.sh (Cases 4–5): instead of grepping
# skills/commit/modes/pr.md for the gated `--auto` append line and the
# "PR mode does NOT" prose, this suite EXTRACTS the real caller-loop fence
# (the slice between `=== BEGIN CANONICAL /land-pr CALLER LOOP ===` and
# `=== END … ===`, plus the explicit-finalize block that lives between the
# END sentinel and the closing fence) via tests/lib/extract-fence.sh, then
# DRIVES it with seeded inputs + a pre-staged /land-pr result file (the
# dispatch in pr.md is a comment — the result file is the injection point).
#
# Each case sets a STATUS / CI_STATUS / PR_STATE / AUTO_FLAG combination in
# the pre-staged result file, runs the real loop, and asserts:
#   - LAND_OUTCOME per combo (the loop's case-arm dispatch),
#   - the explicit-finalize FINAL = complete (merged/created/pr-ready) vs
#     failed, written into fulfilled.commit.<id>'s `status:` line,
#   - requires.land-pr.<id> removed,
#   - `--auto` present in LAND_ARGS iff AUTO_FLAG=1,
#   - the no-result-file path does inline cleanup + exit 1.
#
# Mutating the production loop (e.g. dropping the gated `--auto` append, the
# inline no-result-file cleanup, or a STATUS/CI case arm) makes assertions
# here FAIL — hollow-green protection the old presence-greps could not give.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PR_MODE="$REPO_ROOT/skills/commit/modes/pr.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"
# shellcheck source=tests/lib/landpr-harness.sh
. "$SCRIPT_DIR/lib/landpr-harness.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

if [ ! -f "$PR_MODE" ]; then
  echo "FAIL: commit modes/pr.md not found at $PR_MODE" >&2
  exit 1
fi

echo "=== /commit pr caller loop — extract-and-run (Phase 3) ==="

TMP=$(mktemp -d "/tmp/commit-pr-loop-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ── Extract the loop body (BEGIN..END) + the finalize block (END..fence) ─
# extract_sentinel_block slices the loop body bounded by the BEGIN/END inline
# sentinels. The explicit-finalize block (case "$LAND_OUTCOME" → FINAL=…)
# lives AFTER the END sentinel but inside the SAME fence; a second sentinel
# slice from the END marker to the closing ``` captures it.
LOOP_BODY="$TMP/loop-body.sh"
FINALIZE="$TMP/finalize.sh"
if ! extract_sentinel_block "$PR_MODE" \
      '=== BEGIN CANONICAL /land-pr CALLER LOOP ===' \
      '=== END CANONICAL /land-pr CALLER LOOP ===' > "$LOOP_BODY"; then
  echo "FAIL: could not extract caller-loop BEGIN..END slice from $PR_MODE" >&2
  exit 1
fi
if ! extract_sentinel_block "$PR_MODE" \
      '=== END CANONICAL /land-pr CALLER LOOP ===' \
      '^```$' > "$FINALIZE"; then
  echo "FAIL: could not extract finalize block from $PR_MODE" >&2
  exit 1
fi

# Sanity: extracted slices carry their production landmarks.
if grep -qF 'LAND_OUTCOME=__init__' "$LOOP_BODY" \
   && grep -qF '[ "${AUTO_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --auto"' "$LOOP_BODY" \
   && grep -qF 'produced no result file' "$LOOP_BODY"; then
  pass "[extract] loop body carries LAND_OUTCOME / gated --auto / no-result-file landmarks"
else
  fail "[extract] loop body landmarks" "missing one of LAND_OUTCOME/gated-auto/no-result-file"
fi
if grep -qF 'merged|created|pr-ready) FINAL=complete' "$FINALIZE" \
   && grep -qF 'rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"' "$FINALIZE"; then
  pass "[extract] finalize block carries FINAL=complete map + requires-rm landmarks"
else
  fail "[extract] finalize block landmarks" "missing FINAL-map or requires-rm"
fi

# ── Patch: neuter the resolve-config source; assemble loop+finalize ─────
LOOP_PATCHED="$TMP/loop-patched.sh"
patch_caller_loop "$LOOP_BODY" "$LOOP_PATCHED"
# The loop computes RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt" (NOT
# a $(mktemp) form patch_caller_loop handles), then later `rm -f`s it. Redirect
# it to our pre-staged path so the post-dispatch parser reads our seeded result.
sed -i 's#RESULT_FILE="/tmp/land-pr-result-\$BRANCH_SLUG-\$\$.txt"#RESULT_FILE="$PREPARED_RESULT_FILE"#' "$LOOP_PATCHED"
if grep -qF 'RESULT_FILE="$PREPARED_RESULT_FILE"' "$LOOP_PATCHED"; then
  : # ok
else
  echo "FAIL: RESULT_FILE redirect rewrite did not apply" >&2
  exit 1
fi

RUN_SCRIPT="$TMP/run.sh"
{
  cat "$LOOP_PATCHED"
  printf '\n'
  cat "$FINALIZE"
} > "$RUN_SCRIPT"

# ── git shim (symbolic-ref / git-common-dir) + sanitize script ──────────
SHIM_BIN="$TMP/bin"
MAIN_ROOT_DIR="$TMP/main"
mkdir -p "$SHIM_BIN" "$MAIN_ROOT_DIR/.git"
cat > "$SHIM_BIN/git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-C" ]; then shift 2; fi
case "\${1:-}" in
  rev-parse)
    case "\${2:-}" in
      --git-common-dir) echo "$MAIN_ROOT_DIR/.git" ;;
      *) exit 0 ;;
    esac ;;
  symbolic-ref) echo "feat/seam-harness" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$SHIM_BIN/git"

# run_loop — run the EXTRACTED+patched caller loop in a clean subshell, with a
# pre-staged result file. Sets globals the caller reads:
#   RL_OUT      — loop stdout (key=value lines we emit at end)
#   RL_ERR      — path to captured stderr
#   RL_RC       — loop exit code
#   RL_TRACK    — TRACK_DIR (so the caller can inspect the markers)
# Inputs: pass VAR=value tokens (AUTO_FLAG=…, etc.) before the result-file kvs,
# separated by the literal token "--". A result-file is staged unless the first
# token is "NO_RESULT_FILE".
run_loop() {
  local box; box=$(mktemp -d "$TMP/box.XXXXXX")
  local result_file="$box/result.txt"
  local stage_result=1
  local -a env_tokens=() rf_kvs=()
  local seen_sep=0
  local t
  for t in "$@"; do
    if [ "$t" = "--" ]; then seen_sep=1; continue; fi
    if [ "$t" = "NO_RESULT_FILE" ]; then stage_result=0; continue; fi
    if [ "$seen_sep" -eq 0 ]; then env_tokens+=("$t"); else rf_kvs+=("$t"); fi
  done

  if [ "$stage_result" -eq 1 ]; then
    prepare_result_file "$result_file" "${rf_kvs[@]}"
  fi

  RL_ERR="$box/.stderr"
  RL_TRACK="$MAIN_ROOT_DIR/.zskills/tracking/commit.feat-seam-harness"
  # Clean any prior markers so each case starts fresh.
  rm -f "$RL_TRACK/fulfilled.commit.feat-seam-harness" \
        "$RL_TRACK/requires.land-pr.feat-seam-harness" 2>/dev/null || true

  : > "$box/.stderr"
  RL_OUT=$( exec 2>"$box/.stderr"
    set +e
    set -u
    export PATH="$SHIM_BIN:$PATH"
    export ZSKILLS_SKILLS_ROOT="$REPO_ROOT/skills"
    export CLAUDE_PROJECT_DIR="$REPO_ROOT"
    # Legacy-lane faithful under `set -u`: production fences run WITHOUT
    # `set -u`, so the new resolution idiom's bare ${CLAUDE_PLUGIN_ROOT} token
    # expands empty → else/legacy branch. Bind it EMPTY (not a real path) so the
    # same legacy else-branch is exercised without an unbound-variable abort.
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
    export PREPARED_RESULT_FILE="$result_file"
    # Caller-loop inputs the fence reads from sibling Step 1-3 fences.
    export BRANCH="feat/seam-harness"
    export BRANCH_SLUG="feat-seam-harness"
    export PR_TITLE="Seam Harness"
    export BODY_FILE="$box/body.md"
    : > "$box/body.md"
    seed_caller_loop_inputs
    # Force the fail-arm to settle immediately (no fix-cycle dispatch — the
    # dispatch is a comment anyway) rather than re-loop on a removed result.
    export CI_MAX_ATTEMPTS=0
    # Apply per-case env overrides last so they win.
    local kv
    for kv in "${env_tokens[@]}"; do export "${kv?}"; done
    # shellcheck disable=SC1090
    . "$RUN_SCRIPT" >/dev/null
    # Emit resolved state for assertions.
    printf 'LAND_OUTCOME=%s\n' "${LAND_OUTCOME:-<unset>}"
    printf 'FINAL=%s\n'        "${FINAL:-<unset>}"
    printf 'LAND_ARGS=%s\n'    "${LAND_ARGS:-<unset>}"
    printf 'STATUS=%s\n'       "${STATUS:-<unset>}"
    printf 'CI_STATUS=%s\n'    "${CI_STATUS:-<unset>}"
  )
  RL_RC=$?
  RL_ERR="$box/.stderr"
}

val() { printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1; }

# fulfilled_status — read the `status:` line of the fulfilled.commit marker.
fulfilled_status() {
  local f="$RL_TRACK/fulfilled.commit.feat-seam-harness"
  [ -f "$f" ] && sed -n 's/^status: //p' "$f" | head -1
}
requires_exists() {
  [ -f "$RL_TRACK/requires.land-pr.feat-seam-harness" ] && echo yes || echo no
}

# assert_combo <label> <outcome> <final> <ci-status-result> <env...> -- <result-kvs...>
assert_combo() {
  local label="$1" want_outcome="$2" want_final="$3"; shift 3
  run_loop "$@"
  local got_outcome got_final got_req got_status
  got_outcome=$(val LAND_OUTCOME "$RL_OUT")
  got_final=$(val FINAL "$RL_OUT")
  got_req=$(requires_exists)
  got_status=$(fulfilled_status)
  if [ "$got_outcome" = "$want_outcome" ] \
     && [ "$got_final" = "$want_final" ] \
     && [ "$got_status" = "$want_final" ] \
     && [ "$got_req" = "no" ]; then
    pass "$label → LAND_OUTCOME=$got_outcome, FINAL=$got_final (marker status=$got_status), requires removed"
  else
    fail "$label" "LAND_OUTCOME='$got_outcome'(want $want_outcome) FINAL='$got_final'(want $want_final) marker-status='$got_status' requires='$got_req'"
  fi
}

# ── COMPLETE-class combos (fulfilled status: complete) ──────────────────
# created + CI=pass + PR_STATE=MERGED → merged → complete
assert_combo "1  STATUS=merged CI=pass PR_STATE=MERGED" merged complete \
  -- STATUS=merged CI_STATUS=pass PR_STATE=MERGED
# created + CI=pass + PR_STATE=OPEN → pr-ready → complete
assert_combo "2  STATUS=created CI=pass PR_STATE=OPEN" pr-ready complete \
  -- STATUS=created CI_STATUS=pass PR_STATE=OPEN
# monitored + CI=none → pr-ready → complete
assert_combo "3  STATUS=monitored CI=none" pr-ready complete \
  -- STATUS=monitored CI_STATUS=none
# created + CI=not-monitored → created → complete
assert_combo "4  STATUS=created CI=not-monitored" created complete \
  -- STATUS=created CI_STATUS=not-monitored
# created + CI=pending → pr-ready → complete
assert_combo "5  STATUS=created CI=pending" pr-ready complete \
  -- STATUS=created CI_STATUS=pending

# ── FAILED-class combos (fulfilled status: failed) ──────────────────────
# created + CI=fail + ATTEMPT exhausted (CI_MAX_ATTEMPTS=0) → pr-ci-failing → failed
assert_combo "6  STATUS=created CI=fail (attempts exhausted)" pr-ci-failing failed \
  -- STATUS=created CI_STATUS=fail
# rebase-conflict status → rebase-conflict → failed
assert_combo "7  STATUS=rebase-conflict" rebase-conflict failed \
  -- STATUS=rebase-conflict CI_STATUS=
# push-failed status → push-failed → failed
assert_combo "8  STATUS=push-failed" push-failed failed \
  -- STATUS=push-failed CI_STATUS= REASON=boom
# behind-thrash status → behind-thrash → failed
assert_combo "9  STATUS=behind-thrash" behind-thrash failed \
  -- STATUS=behind-thrash CI_STATUS=
# auto-rebase-blocked status → auto-rebase-blocked → failed
assert_combo "10 STATUS=auto-rebase-blocked" auto-rebase-blocked failed \
  -- STATUS=auto-rebase-blocked CI_STATUS= REASON=blk
# unknown STATUS → unknown-status-<X> → failed
assert_combo "11 STATUS=weird (unknown)" unknown-status-weird failed \
  -- STATUS=weird CI_STATUS=pass

# ── --auto gate: present iff AUTO_FLAG=1 ────────────────────────────────
run_loop AUTO_FLAG=1 STATUS=created CI_STATUS=pass PR_STATE=MERGED \
  -- STATUS=merged CI_STATUS=pass PR_STATE=MERGED
if printf '%s' "$(val LAND_ARGS "$RL_OUT")" | grep -qF -- '--auto'; then
  pass "12 AUTO_FLAG=1 → LAND_ARGS includes --auto"
else
  fail "12 AUTO_FLAG=1 --auto" "LAND_ARGS='$(val LAND_ARGS "$RL_OUT")'"
fi
run_loop AUTO_FLAG=0 STATUS=created CI_STATUS=pass PR_STATE=MERGED \
  -- STATUS=merged CI_STATUS=pass PR_STATE=MERGED
if printf '%s' "$(val LAND_ARGS "$RL_OUT")" | grep -qF -- '--auto'; then
  fail "13 AUTO_FLAG=0 omits --auto" "LAND_ARGS='$(val LAND_ARGS "$RL_OUT")' unexpectedly has --auto"
else
  pass "13 AUTO_FLAG=0 → LAND_ARGS omits --auto"
fi

# ── No-result-file path: inline cleanup + exit 1 ────────────────────────
run_loop NO_RESULT_FILE STATUS=created CI_STATUS=pass -- STATUS=created CI_STATUS=pass
if [ "$RL_RC" -eq 1 ] && grep -qF 'produced no result file' "$RL_ERR"; then
  pass "14 no result file → exit 1 with 'produced no result file' error"
else
  fail "14 no-result exit/err" "rc='$RL_RC' err='$(cat "$RL_ERR")'"
fi
# Inline cleanup ran: requires removed, fulfilled marked failed.
if [ "$(requires_exists)" = "no" ] && [ "$(fulfilled_status)" = "failed" ]; then
  pass "15 no result file → inline cleanup (requires removed, fulfilled status=failed)"
else
  fail "15 no-result inline cleanup" "requires='$(requires_exists)' fulfilled-status='$(fulfilled_status)'"
fi

# ── Migrated from test-commit.sh Case 5 (prose-gate documentation) ──────
# The pre-#236 blanket "Auto-merge (no `--auto` passed to `/land-pr`)" must be
# gone; the gated prose ("unless the positional `automerge` token is passed")
# must document the gate. (Post auto/automerge split: `automerge` is the token
# that gates the merge request; bare `auto` is unattended-only.) Behavioral
# cases 12/13 prove the gate WORKS; this keeps the doc invariant the old
# test-commit.sh Case 5 asserted.
OLD_BLANKET=$(grep -cE 'Auto-merge \(no `--auto` passed to `/land-pr`\)' "$PR_MODE" 2>/dev/null)
NEW_GATED=$(grep -cE 'unless the positional `automerge` token is passed' "$PR_MODE" 2>/dev/null)
if [ "${OLD_BLANKET:-0}" -eq 0 ] && [ "${NEW_GATED:-0}" -ge 1 ]; then
  pass "16 modes/pr.md 'PR mode does NOT' note documents the auto gate (migrated, #236)"
else
  fail "16 prose gate" "old-blanket=${OLD_BLANKET:-0} (want 0) new-gated=${NEW_GATED:-0} (want >=1)"
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
