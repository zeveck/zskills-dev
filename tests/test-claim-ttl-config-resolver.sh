#!/bin/bash
# tests/test-claim-ttl-config-resolver.sh — unit tests for the
# zskills-resolve-config.sh parse of execution.claim_ttl_seconds (issue
# #574, PR #544 Phase 1 adjacent surface).
#
# Covers four resolver edge cases that the existing
# tests/test-fix-issues-claim-script.sh suite bypasses by `export
# ZSKILLS_CLAIM_TTL_SECONDS=...` directly:
#   - field absent     -> default 7200
#   - field = 1800     -> 1800 (valid)
#   - field = 30       -> 7200 (sub-60 floor rejected, fallback to default)
#   - field = "30"     -> 7200 (string, [ -ge 60 ] guard rejects)
#
# Strategy: each case writes a minimal .claude/zskills-config.json under a
# tmp $CLAUDE_PROJECT_DIR, then sources zskills-resolve-config.sh in a
# subshell (so the export/var bleed doesn't leak across cases). Subshell
# isolation also lets us `unset CLAUDE_PROJECT_DIR` per-case despite the
# parent test-harness having set it.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER_SH="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-claim-ttl-config-resolver-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT for inspection" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

if [ ! -f "$RESOLVER_SH" ]; then
  echo "FATAL: zskills-resolve-config.sh missing at $RESOLVER_SH" >&2
  exit 1
fi

echo "=== zskills-resolve-config.sh claim_ttl_seconds tests ==="

# Helper: writes a config json with the given execution body, then sources
# the resolver in a subshell from inside a fresh git repo (resolver's
# git-common-dir fallback requires being inside one). Echoes the resolved
# ZSKILLS_CLAIM_TTL_SECONDS to stdout.
#
# Args:
#   $1 — case label (used as subdir name under SCRATCH_ROOT)
#   $2 — JSON body for .claude/zskills-config.json (full content)
resolve_in_case() {
  local label="$1"
  local config_body="$2"
  local case_root="$SCRATCH_ROOT/$label"
  mkdir -p "$case_root/.claude"
  printf '%s' "$config_body" > "$case_root/.claude/zskills-config.json"
  # Init a git repo so the resolver's git-common-dir fallback path works
  # if CLAUDE_PROJECT_DIR somehow isn't honored. We set it explicitly.
  (cd "$case_root" && git init -q && git config user.email "t@t" && git config user.name "t" && git commit --allow-empty -q -m "init") || return 1
  # Subshell: clear and reset CLAUDE_PROJECT_DIR; clear inherited TTL var so
  # the resolver's own defaulting + parse is what's under test (not the
  # parent harness's export).
  (
    unset ZSKILLS_CLAIM_TTL_SECONDS
    export CLAUDE_PROJECT_DIR="$case_root"
    cd "$case_root" || exit 1
    # shellcheck source=/dev/null
    . "$RESOLVER_SH" >/dev/null 2>&1
    echo "$ZSKILLS_CLAIM_TTL_SECONDS"
  )
}

# ───────────────────────────────────────────────────────────────────────
# Test D: field present (= 1800) -> 1800.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_in_case "d_present_1800" '{"execution":{"claim_ttl_seconds":1800}}')
if [ "$got" = "1800" ]; then
  pass "execution.claim_ttl_seconds=1800 -> ZSKILLS_CLAIM_TTL_SECONDS=1800"
else
  fail "claim_ttl_seconds=1800 resolved" "expected 1800, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Test E: field absent (config has no execution.claim_ttl_seconds, but the
# enclosing execution object exists) -> default 7200.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_in_case "e_absent" '{"execution":{"max_concurrent_worktrees":3}}')
if [ "$got" = "7200" ]; then
  pass "execution.claim_ttl_seconds absent -> ZSKILLS_CLAIM_TTL_SECONDS=7200 (default)"
else
  fail "claim_ttl_seconds absent resolved to default" "expected 7200, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Test F: field below sub-60 floor (= 30) -> 7200 (default kept).
# Schema documents `min 60`; the resolver enforces the floor via
# `[ "$_ZSK_TTL" -ge 60 ]`. Sub-60 values must not be honored.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_in_case "f_below_floor" '{"execution":{"claim_ttl_seconds":30}}')
if [ "$got" = "7200" ]; then
  pass "execution.claim_ttl_seconds=30 (below floor) -> ZSKILLS_CLAIM_TTL_SECONDS=7200 (rejected)"
else
  fail "claim_ttl_seconds sub-60 floor enforced" "expected 7200, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Test G: malformed value (string "not-a-number" where int is expected)
# -> 7200 (Python-parse path returns the string, the bash `-ge 60` guard
# rejects non-numeric and the initializer default of 7200 is kept).
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_in_case "g_malformed" '{"execution":{"claim_ttl_seconds":"not-a-number"}}')
if [ "$got" = "7200" ]; then
  pass "execution.claim_ttl_seconds=\"not-a-number\" -> ZSKILLS_CLAIM_TTL_SECONDS=7200 (parse-fallback)"
else
  fail "claim_ttl_seconds string fallback" "expected 7200, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
