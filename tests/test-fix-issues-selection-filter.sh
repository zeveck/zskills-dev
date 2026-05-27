#!/bin/bash
# test-fix-issues-selection-filter.sh — selection-aware filter for /fix-issues
# Phase 2 candidate picker (closes #641).
#
# Mirror of tests/test-plan-claim-selection-filter.sh +
# test-plan-claim-filter-edge-cases.sh, adapted for bare-integer input.
#
# Synthesise `.zskills/claims/issue-42/claim.json` via `claim-issue.sh
# acquire 42 --pipeline-id ... --sprint-id ...` (exercises the real schema —
# DA2.12 equivalent for issues), feed CANDIDATE_ISSUES=[42, 43] through
# filter-in-flight-issue-claims.sh, assert:
#   (a) `42` is filtered out of stdout
#   (b) `43` is preserved in stdout
#   (c) stderr contains "Skipped 1 issue(s) currently in-flight: 42"
#   (d) filter exits 0
#
# Plus edge cases mirroring the plan-side coverage:
#   - Empty claims root           → passthrough
#   - Missing claims root         → passthrough
#   - Missing claim.json          → claim dir skipped silently
#   - Malformed claim.json        → claim dir skipped silently
#   - Empty stdin                 → empty stdout
#   - Non-issue-* dir             → ignored (e.g., plan-foo)
#
# Honest scope (DA2.7 mirror): this filter closes the STEADY-STATE race
# only (claim already on disk when both /fix-issues invocations run
# filter). It does NOT close the FRESH-START race (both pipelines observe
# empty claims-dir before either acquires); that residual window is
# bounded by claim-issue.sh's acquire-EEXIST atomic mkdir → exit 10
# contract. Same architecture as /work-on-plans + /run-plan.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/fix-issues/scripts/filter-in-flight-issue-claims.sh"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="/tmp/test-fix-issues-selection-filter-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  if [ -d "$SCRATCH" ]; then
    find "$SCRATCH" -type d -exec chmod u+rwx {} \; 2>/dev/null || true
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

echo "=== /fix-issues selection filter (#641) ==="

# Sanity: filter script + claim-issue.sh exist and are executable.
if [ ! -x "$FILTER" ]; then
  fail "filter script executable" "$FILTER not found or not executable"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
if [ ! -f "$CLAIM_SH" ]; then
  fail "claim-issue.sh present" "$CLAIM_SH not found"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
pass "filter + claim-issue.sh present (claim-issue.sh invoked via bash; not chmod +x by design)"

# Helpers ---------------------------------------------------------------------
make_fixture() {
  local f="$1"
  mkdir -p "$f"
  (
    cd "$f"
    git init -q
    git config user.email "t@t"
    git config user.name "t"
    git commit --allow-empty -q -m "init"
  ) >/dev/null 2>&1
}

run_filter_in() {
  local fixture="$1"
  local input="$2"
  STDOUT="$SCRATCH/stdout.$$"
  STDERR="$SCRATCH/stderr.$$"
  (
    cd "$fixture"
    printf '%s' "$input" | bash "$FILTER"
  ) >"$STDOUT" 2>"$STDERR"
  RC=$?
}

# === Happy path ===
# Build a real git fixture so MAIN_ROOT resolves predictably.
FIXTURE="$SCRATCH/happy"
make_fixture "$FIXTURE"

# Acquire a real claim for issue 42.
(
  cd "$FIXTURE"
  bash "$CLAIM_SH" acquire 42 \
    --pipeline-id "fix-issues.test" \
    --sprint-id   "sprint.test"
) >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "acquire claim for 42" "exit $rc"
  echo "Results: $PASS_COUNT passed, $((FAIL_COUNT + 1)) failed"
  exit 1
fi
pass "acquired claim issue-42 via claim-issue.sh acquire"

if [ ! -f "$FIXTURE/.zskills/claims/issue-42/claim.json" ]; then
  fail "claim.json on disk" "missing $FIXTURE/.zskills/claims/issue-42/claim.json"
else
  pass "claim.json present on disk"
fi

# Feed bare integers (one per line) — input shape is integers, NOT TSV.
INPUT=$'42\n43'
STDOUT_FILE="$SCRATCH/stdout.txt"
STDERR_FILE="$SCRATCH/stderr.txt"
(
  cd "$FIXTURE"
  printf '%s' "$INPUT" | bash "$FILTER"
) >"$STDOUT_FILE" 2>"$STDERR_FILE"
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "filter exits 0"
else
  fail "filter exits 0" "got rc=$rc"
fi

# Assertion (a): 42 is filtered out.
if ! grep -qE '^42$' "$STDOUT_FILE"; then
  pass "42 is filtered out of stdout"
else
  fail "42 is filtered out" "found 42 in stdout: $(cat "$STDOUT_FILE")"
fi

# Assertion (b): 43 is preserved.
if grep -qE '^43$' "$STDOUT_FILE"; then
  pass "43 is preserved in stdout"
else
  fail "43 preserved" "stdout: $(cat "$STDOUT_FILE")"
fi

# Assertion (c): stderr Skipped-N line.
if grep -qE 'Skipped 1 issue\(s\) currently in-flight: 42' "$STDERR_FILE"; then
  pass "stderr contains 'Skipped 1 issue(s) currently in-flight: 42'"
else
  fail "stderr Skipped-N line" "stderr: $(cat "$STDERR_FILE")"
fi

# === Edge cases ==============================================================

# --- 1. Missing claims root → passthrough ----------------------------------
test_missing_claims_root() {
  local f="$SCRATCH/case_missing_root"
  make_fixture "$f"
  # No .zskills/claims dir at all.
  run_filter_in "$f" $'7\n8'
  if [ "$RC" -eq 0 ] \
     && grep -qE '^7$' "$STDOUT" \
     && grep -qE '^8$' "$STDOUT" \
     && [ ! -s "$STDERR" ]; then
    pass "missing claims root → passthrough"
  else
    fail "missing claims root" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 2. Empty claims root → passthrough ------------------------------------
test_empty_claims_root() {
  local f="$SCRATCH/case_empty_root"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims"
  run_filter_in "$f" $'7\n8'
  if [ "$RC" -eq 0 ] \
     && grep -qE '^7$' "$STDOUT" \
     && grep -qE '^8$' "$STDOUT" \
     && [ ! -s "$STDERR" ]; then
    pass "empty claims root → passthrough"
  else
    fail "empty claims root" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 3. claim dir without claim.json → ignored (not in-flight) -------------
test_missing_claim_json() {
  local f="$SCRATCH/case_missing_json"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims/issue-100"
  # No claim.json inside.
  run_filter_in "$f" $'100\n101'
  if [ "$RC" -eq 0 ] \
     && grep -qE '^100$' "$STDOUT" \
     && grep -qE '^101$' "$STDOUT"; then
    pass "missing claim.json → claim dir skipped; both preserved"
  else
    fail "missing claim.json" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 4. Malformed claim.json → ignored -------------------------------------
test_malformed_claim_json() {
  local f="$SCRATCH/case_malformed_json"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims/issue-200"
  echo "this is not json {" > "$f/.zskills/claims/issue-200/claim.json"
  run_filter_in "$f" $'200\n201'
  if [ "$RC" -eq 0 ] \
     && grep -qE '^200$' "$STDOUT" \
     && grep -qE '^201$' "$STDOUT"; then
    pass "malformed claim.json → claim skipped; both preserved"
  else
    fail "malformed claim.json" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 5. Non-issue-* directory in claims root → ignored ---------------------
test_non_issue_dir() {
  local f="$SCRATCH/case_non_issue"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims/plan-foo"
  echo '{"pipeline_id":"x","slug":"foo"}' > "$f/.zskills/claims/plan-foo/claim.json"
  run_filter_in "$f" $'300\n301'
  if [ "$RC" -eq 0 ] \
     && grep -qE '^300$' "$STDOUT" \
     && grep -qE '^301$' "$STDOUT"; then
    pass "non-issue-* dir (plan-foo) → ignored; both preserved"
  else
    fail "non-issue-* dir ignored" "rc=$RC stdout=$(cat "$STDOUT")"
  fi
}

# --- 6. Empty stdin → empty stdout (no crash) ------------------------------
test_empty_stdin() {
  local f="$SCRATCH/case_empty_stdin"
  make_fixture "$f"
  STDOUT="$SCRATCH/stdout.empty"
  STDERR="$SCRATCH/stderr.empty"
  ( cd "$f" && : | bash "$FILTER" ) >"$STDOUT" 2>"$STDERR"
  RC=$?
  if [ "$RC" -eq 0 ] && [ ! -s "$STDOUT" ]; then
    pass "empty stdin → empty stdout, exit 0"
  else
    fail "empty stdin" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 7. Unreadable claims root → diagnostic + passthrough ------------------
test_unreadable_claims_root() {
  # Skip if running as root (chmod 000 doesn't block root).
  if [ "$(id -u)" -eq 0 ]; then
    pass "unreadable claims root (SKIPPED: running as root, perm check no-ops)"
    return
  fi
  local f="$SCRATCH/case_unreadable"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims"
  chmod 000 "$f/.zskills/claims"
  run_filter_in "$f" $'400\n401'
  # Restore perms immediately so cleanup works.
  chmod u+rwx "$f/.zskills/claims" 2>/dev/null || true
  if [ "$RC" -eq 0 ] \
     && grep -qE '^400$' "$STDOUT" \
     && grep -qE '^401$' "$STDOUT" \
     && grep -qF 'cannot read' "$STDERR"; then
    pass "unreadable claims root → diagnostic line + passthrough"
  else
    fail "unreadable claims root" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

test_missing_claims_root
test_empty_claims_root
test_missing_claim_json
test_malformed_claim_json
test_non_issue_dir
test_empty_stdin
test_unreadable_claims_root

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
