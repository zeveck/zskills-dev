#!/bin/bash
# tests/test-plan-claim-ttl-config-resolver.sh — Phase 1 W1.7.
#
# Asserts the 5-level TTL precedence chain implemented inline in
# claim-plan.sh resolve_ttl():
#
#   1. env  ZSKILLS_PLAN_CLAIM_TTL_SECONDS    (plan-specific override)
#   2. config execution.plan_claim_ttl_seconds (plan-specific)
#   3. env  ZSKILLS_CLAIM_TTL_SECONDS         (shared fallback)
#   4. config execution.claim_ttl_seconds      (shared fallback)
#   5. built-in 7200
#
# Each level is a separate sub-test. To exercise resolve_ttl() in
# isolation we source the script (its body is dual-mode: when sourced, it
# only DEFINES functions because the bottom dispatch is guarded by the
# BASH_SOURCE check) and call resolve_ttl directly — after setting up
# MAIN_ROOT (via cd into a git fixture) and a per-case .claude/zskills-config.json.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-ttl-config-resolver-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

if [ ! -f "$CLAIM_SH" ]; then
  echo "FATAL: claim-plan.sh missing at $CLAIM_SH" >&2
  exit 1
fi

# Helper: writes a config json with the given execution body (or omits
# the file entirely if $2 is the literal "NO_CONFIG"). Sets env vars per
# $3 (key=val ; separated, or "" for none), then invokes claim-plan.sh
# acquire on a fixture so resolve_ttl runs; we read the resolved TTL by
# instead sourcing the script in a subshell and calling resolve_ttl
# directly.
#
# Args:
#   $1 — case label (subdir name)
#   $2 — JSON body (or "NO_CONFIG" to skip writing the file)
#   $3 — env exports (semicolon-separated key=val pairs, e.g.
#        "ZSKILLS_PLAN_CLAIM_TTL_SECONDS=1234")
resolve_ttl_in_case() {
  local label="$1"
  local config_body="$2"
  local env_exports="$3"
  local case_root="$SCRATCH_ROOT/$label"
  mkdir -p "$case_root/.claude"
  if [ "$config_body" != "NO_CONFIG" ]; then
    printf '%s' "$config_body" > "$case_root/.claude/zskills-config.json"
  fi
  # Init a git repo so resolve_main_root works.
  (cd "$case_root" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
  # Subshell: clear inherited TTL env vars, apply per-case env, then
  # source claim-plan.sh and call resolve_ttl. Per-case env wins.
  (
    unset ZSKILLS_PLAN_CLAIM_TTL_SECONDS
    unset ZSKILLS_CLAIM_TTL_SECONDS
    export CLAUDE_PROJECT_DIR="$case_root"
    cd "$case_root" || exit 1
    # Apply env exports.
    if [ -n "$env_exports" ]; then
      # shellcheck disable=SC2086
      IFS=';' read -ra _PAIRS <<< "$env_exports"
      for pair in "${_PAIRS[@]}"; do
        [ -z "$pair" ] && continue
        export "$pair"
      done
    fi
    # Resolve MAIN_ROOT — claim-plan.sh's resolve_ttl() depends on
    # MAIN_ROOT being set (it reads .claude/zskills-config.json relative
    # to MAIN_ROOT in the fallback path). Sourcing the script defines
    # the functions; we then call them.
    # shellcheck source=/dev/null
    . "$CLAIM_SH"
    resolve_main_root >/dev/null 2>&1 || true
    resolve_ttl
  )
}

echo "=== claim-plan.sh resolve_ttl 5-level precedence chain ==="

# ───────────────────────────────────────────────────────────────────────
# Level 1: env ZSKILLS_PLAN_CLAIM_TTL_SECONDS wins (plan-specific override).
# Config also has both keys but env takes precedence.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_ttl_in_case "L1_env_plan_specific" \
  '{"execution":{"plan_claim_ttl_seconds":5555,"claim_ttl_seconds":6666}}' \
  "ZSKILLS_PLAN_CLAIM_TTL_SECONDS=1234")
if [ "$got" = "1234" ]; then
  pass "Level 1: env ZSKILLS_PLAN_CLAIM_TTL_SECONDS overrides all (=1234)"
else
  fail "Level 1 env plan-specific" "expected 1234, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Level 2: config execution.plan_claim_ttl_seconds — env unset.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_ttl_in_case "L2_config_plan_specific" \
  '{"execution":{"plan_claim_ttl_seconds":1234,"claim_ttl_seconds":9999}}' \
  "")
if [ "$got" = "1234" ]; then
  pass "Level 2: config execution.plan_claim_ttl_seconds=1234 (plan-specific wins over shared)"
else
  fail "Level 2 config plan-specific" "expected 1234, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Level 3: env ZSKILLS_CLAIM_TTL_SECONDS (shared fallback) — plan key absent.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_ttl_in_case "L3_env_shared" \
  '{"execution":{"claim_ttl_seconds":9999}}' \
  "ZSKILLS_CLAIM_TTL_SECONDS=1234")
if [ "$got" = "1234" ]; then
  pass "Level 3: env ZSKILLS_CLAIM_TTL_SECONDS=1234 (shared env beats shared config)"
else
  fail "Level 3 env shared" "expected 1234, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Level 4: config execution.claim_ttl_seconds — all envs unset, no plan-specific.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_ttl_in_case "L4_config_shared" \
  '{"execution":{"claim_ttl_seconds":1234}}' \
  "")
if [ "$got" = "1234" ]; then
  pass "Level 4: config execution.claim_ttl_seconds=1234 (shared config fallback)"
else
  fail "Level 4 config shared" "expected 1234, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Level 5: built-in 7200 — no envs, no config keys at all.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_ttl_in_case "L5_builtin" \
  '{"execution":{}}' \
  "")
if [ "$got" = "7200" ]; then
  pass "Level 5: built-in default 7200 when all sources empty"
else
  fail "Level 5 built-in" "expected 7200, got '$got'"
fi

# Also: NO_CONFIG file at all -> built-in 7200.
got=$(resolve_ttl_in_case "L5_no_config" "NO_CONFIG" "")
if [ "$got" = "7200" ]; then
  pass "Level 5: built-in default 7200 when config file absent"
else
  fail "Level 5 no-config file" "expected 7200, got '$got'"
fi

# ───────────────────────────────────────────────────────────────────────
# Floor enforcement: sub-60 values (env or config) fall back to 7200.
# ───────────────────────────────────────────────────────────────────────
got=$(resolve_ttl_in_case "floor_env_plan" '{"execution":{}}' "ZSKILLS_PLAN_CLAIM_TTL_SECONDS=30")
if [ "$got" = "7200" ]; then
  pass "Floor: env ZSKILLS_PLAN_CLAIM_TTL_SECONDS=30 -> 7200 (sub-60 rejected)"
else
  fail "Floor env plan sub-60" "expected 7200, got '$got'"
fi

got=$(resolve_ttl_in_case "floor_config_plan" '{"execution":{"plan_claim_ttl_seconds":30}}' "")
if [ "$got" = "7200" ]; then
  pass "Floor: config plan_claim_ttl_seconds=30 -> 7200 (sub-60 rejected)"
else
  fail "Floor config plan sub-60" "expected 7200, got '$got'"
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
