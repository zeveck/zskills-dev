#!/bin/bash
# test-plan-claim-filter-edge-cases.sh — AC2b.3.
#
# Filter must degrade gracefully on broken-claims-dir inputs. Coverage:
#   1. Empty claims root           → filter is a no-op (passthrough).
#   2. Missing claims root         → filter is a no-op (passthrough).
#   3. Missing claim.json          → claim dir skipped silently (not
#                                    treated as in-flight; sweep reaps).
#   4. Malformed claim.json        → claim dir skipped silently.
#   5. Non-plan-* directory        → ignored.
#   6. Slug with invalid shape     → ignored.
#   7. Unreadable claims root      → single stderr diagnostic + passthrough.
#
# All cases: exit 0; original READY_LINES preserved unless a valid
# in-flight slug actually matches.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH="/tmp/test-plan-claim-filter-edge-cases-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  # Restore perms in case test 7 left a chmod 000 dir.
  if [ -d "$SCRATCH" ]; then
    find "$SCRATCH" -type d -exec chmod u+rwx {} \; 2>/dev/null || true
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH"

echo "=== plan-claim filter edge cases (AC2b.3) ==="

# Helper: build a git fixture and run the filter against given input.
# Sets RC, STDOUT, STDERR globals.
run_filter_in() {
  local fixture="$1"
  local input="$2"
  STDOUT="$SCRATCH/stdout.$$"
  STDERR="$SCRATCH/stderr.$$"
  (
    cd "$fixture"
    printf '%s\n' "$input" | bash "$FILTER"
  ) >"$STDOUT" 2>"$STDERR"
  RC=$?
}

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

# --- 1. Missing claims root → passthrough --------------------------------
test_missing_claims_root() {
  local f="$SCRATCH/case1"
  make_fixture "$f"
  # No .zskills/claims dir at all.
  run_filter_in "$f" "alpha"
  if [ "$RC" -eq 0 ] && grep -qE '^alpha$' "$STDOUT" && [ ! -s "$STDERR" ]; then
    pass "missing claims root → passthrough (alpha preserved, no stderr)"
  else
    fail "missing claims root" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 2. Empty claims root → passthrough ----------------------------------
test_empty_claims_root() {
  local f="$SCRATCH/case2"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims"
  run_filter_in "$f" "alpha"
  if [ "$RC" -eq 0 ] && grep -qE '^alpha$' "$STDOUT" && [ ! -s "$STDERR" ]; then
    pass "empty claims root → passthrough"
  else
    fail "empty claims root" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 3. claim dir without claim.json → ignored (not in-flight) -----------
test_missing_claim_json() {
  local f="$SCRATCH/case3"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims/plan-alpha"
  # No claim.json inside.
  run_filter_in "$f" "alpha"
  if [ "$RC" -eq 0 ] && grep -qE '^alpha$' "$STDOUT"; then
    pass "missing claim.json → claim dir skipped; alpha preserved"
  else
    fail "missing claim.json" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 4. Malformed claim.json → ignored -----------------------------------
test_malformed_claim_json() {
  local f="$SCRATCH/case4"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims/plan-alpha"
  echo "this is not json {" > "$f/.zskills/claims/plan-alpha/claim.json"
  run_filter_in "$f" "alpha"
  if [ "$RC" -eq 0 ] && grep -qE '^alpha$' "$STDOUT"; then
    pass "malformed claim.json → claim skipped; alpha preserved"
  else
    fail "malformed claim.json" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 5. Non-plan-* directory in claims root → ignored --------------------
test_non_plan_dir() {
  local f="$SCRATCH/case5"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims/issue-42"
  echo '{"pipeline_id":"x","slug":"42"}' > "$f/.zskills/claims/issue-42/claim.json"
  run_filter_in "$f" "alpha"
  if [ "$RC" -eq 0 ] && grep -qE '^alpha$' "$STDOUT"; then
    pass "non-plan-* dir (issue-42) → ignored; alpha preserved"
  else
    fail "non-plan-* dir ignored" "rc=$RC stdout=$(cat "$STDOUT")"
  fi
}

# --- 6. Invalid-shape slug in dir name → ignored -------------------------
test_invalid_slug_shape() {
  local f="$SCRATCH/case6"
  make_fixture "$f"
  # plan-_underscore is invalid kebab-case (leading underscore inside slug).
  mkdir -p "$f/.zskills/claims/plan-_bad"
  echo '{"pipeline_id":"x","slug":"_bad"}' > "$f/.zskills/claims/plan-_bad/claim.json"
  run_filter_in "$f" "alpha"
  if [ "$RC" -eq 0 ] && grep -qE '^alpha$' "$STDOUT"; then
    pass "invalid-shape slug dir → ignored; alpha preserved"
  else
    fail "invalid-shape slug ignored" "rc=$RC stdout=$(cat "$STDOUT")"
  fi
}

# --- 7. Unreadable claims root → diagnostic + passthrough ----------------
test_unreadable_claims_root() {
  # Skip if running as root (chmod 000 doesn't block root).
  if [ "$(id -u)" -eq 0 ]; then
    pass "unreadable claims root (SKIPPED: running as root, perm check no-ops)"
    return
  fi
  local f="$SCRATCH/case7"
  make_fixture "$f"
  mkdir -p "$f/.zskills/claims"
  chmod 000 "$f/.zskills/claims"
  run_filter_in "$f" "alpha"
  # Restore perms immediately so cleanup works.
  chmod u+rwx "$f/.zskills/claims" 2>/dev/null || true
  if [ "$RC" -eq 0 ] \
     && grep -qE '^alpha$' "$STDOUT" \
     && grep -qF 'cannot read' "$STDERR"; then
    pass "unreadable claims root → diagnostic line + alpha passthrough"
  else
    fail "unreadable claims root" "rc=$RC stdout=$(cat "$STDOUT") stderr=$(cat "$STDERR")"
  fi
}

# --- 8. Empty stdin → empty stdout (no crash) ---------------------------
test_empty_stdin() {
  local f="$SCRATCH/case8"
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

test_missing_claims_root
test_empty_claims_root
test_missing_claim_json
test_malformed_claim_json
test_non_plan_dir
test_invalid_slug_shape
test_unreadable_claims_root
test_empty_stdin

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
