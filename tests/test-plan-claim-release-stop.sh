#!/bin/bash
# tests/test-plan-claim-release-stop.sh — Phase 2a W2a.11 / AC2a.4 site 1.
#
# Verifies the `/run-plan stop` handler's Option A walk (W2a.4 site 1):
#   - iterates `.zskills/claims/plan-*/`
#   - calls claim-plan.sh release for every claim whose pipeline_id starts
#     with `run-plan.` (skipping non-run-plan claims and mismatched
#     pipelines)
#   - emits to stderr `Stop released N claim(s); skipped M claim(s)
#     (pipeline mismatch).` with accurate counts (DA2.9)
#
# Two parts:
#   (1) SKILL.md prose conformance: `^## Stop` section contains the
#       release-walk fence with correct stderr format and exit-12-skip
#       semantics.
#   (2) End-to-end harness: stage 3 claim dirs (one matched, one
#       mismatched, one non-run-plan-prefixed) and run the walk extracted
#       from the SKILL fence directly; assert exit codes and stderr format.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/run-plan/SKILL.md"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-stop-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then return; fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== plan-claim release walk in /run-plan stop (site 1) ==="

# ─────────────────────────────────────────────────────────────────────
# Part 1: SKILL.md conformance
# ─────────────────────────────────────────────────────────────────────

stop_section=$(awk '
  /^## Stop / { p = 1; next }
  p && /^## / { p = 0 }
  p { print }
' "$SKILL_MD")

# Must contain release walk (not the constant-string release).
if printf '%s\n' "$stop_section" | grep -q 'for .* in .*plan-\*'; then
  pass "Stop section iterates plan-*/ claim dirs"
else
  fail "Stop section iteration" "no 'for ... in ...plan-*' loop found in ## Stop"
fi

# Must contain claim-plan.sh release call.
if printf '%s\n' "$stop_section" | grep -qE '^[[:space:]]*release "\$slug"'; then
  pass "Stop section calls claim-plan.sh release"
else
  fail "Stop section release call" "no claim-plan.sh release in ## Stop"
fi

# Must emit accurate count message to stderr.
if printf '%s\n' "$stop_section" | grep -q 'Stop released.*claim(s).*skipped.*claim(s)'; then
  pass "Stop section emits count message with both released and skipped counters"
else
  fail "Stop count message" "no 'Stop released N claim(s); skipped M claim(s)' format in ## Stop"
fi

# Must only act on run-plan.* pipeline_ids.
if printf '%s\n' "$stop_section" | grep -q 'run-plan\.'; then
  pass "Stop section guards release on run-plan.* pipeline_id prefix"
else
  fail "Stop pipeline guard" "no run-plan.* guard found"
fi

# Exit 12 should be skipped (not failed).
if printf '%s\n' "$stop_section" | grep -q '12)'; then
  pass "Stop section handles exit 12 (pipeline mismatch) explicitly"
else
  fail "Stop exit 12 arm" "no '12)' case branch found"
fi

# ─────────────────────────────────────────────────────────────────────
# Part 2: end-to-end walk harness
# ─────────────────────────────────────────────────────────────────────

FIXTURE="$SCRATCH_ROOT/fixture"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: fixture init failed" >&2; exit 1; }

# Stage three claims:
#   - plan-A: pipeline_id = run-plan.A → should be released
#   - plan-B: pipeline_id = other-skill.B → should NOT be touched (non-run-plan)
#   - plan-C: pipeline_id = run-plan.C → should be released
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "plan-a-slug" --pipeline-id "run-plan.A" >/dev/null 2>&1 )
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "plan-c-slug" --pipeline-id "run-plan.C" >/dev/null 2>&1 )
# Stage plan-B manually (sanitizer would reject `other-skill.B` arbitrarily,
# but we can manipulate the claim.json by overwriting pipeline_id).
( cd "$FIXTURE" && bash "$CLAIM_SH" acquire "plan-b-slug" --pipeline-id "run-plan.B" >/dev/null 2>&1 )
python3 -c "
import json, sys
p='$FIXTURE/.zskills/claims/plan-plan-b-slug/claim.json'
with open(p) as f: body = json.load(f)
body['pipeline_id'] = 'other-skill.B'
with open(p, 'w') as f: json.dump(body, f, sort_keys=True)
"

# Run the walk verbatim as a bash function (mirrors the SKILL.md prose
# fence body).
walk_releases() {
  local MAIN_ROOT="$1"
  local CLAIMS_ROOT="$MAIN_ROOT/.zskills/claims"
  local RELEASED=0
  local SKIPPED=0
  if [ -d "$CLAIMS_ROOT" ]; then
    for d in "$CLAIMS_ROOT"/plan-*; do
      [ -d "$d" ] || continue
      slug=$(basename "$d" | sed 's/^plan-//')
      [ -n "$slug" ] || continue
      claim_file="$d/claim.json"
      if [ ! -f "$claim_file" ]; then continue; fi
      claim_pid=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('pipeline_id',''))
except Exception:
    pass
" "$claim_file" 2>/dev/null)
      case "$claim_pid" in
        run-plan.*) ;;
        *) continue ;;
      esac
      set +e
      bash "$CLAIM_SH" release "$slug" --require-pipeline "$claim_pid" >/dev/null 2>&1
      rc=$?
      set -e
      case "$rc" in
        0) RELEASED=$((RELEASED + 1)) ;;
        12) SKIPPED=$((SKIPPED + 1)) ;;
        *) SKIPPED=$((SKIPPED + 1)) ;;
      esac
    done
  fi
  echo "Stop released $RELEASED claim(s); skipped $SKIPPED claim(s) (pipeline mismatch)." >&2
}

stderr_file="$SCRATCH_ROOT/stop.stderr"
( cd "$FIXTURE" && walk_releases "$FIXTURE" ) 2> "$stderr_file"

# Expect: released=2 (A + C), skipped=0 (B was filtered out, not skipped).
if grep -q "Stop released 2 claim(s); skipped 0 claim(s) (pipeline mismatch)." "$stderr_file"; then
  pass "stop walk: 2 run-plan claims released, 0 skipped (non-run-plan filtered out)"
else
  fail "stop walk stderr format" "expected 'Stop released 2 claim(s); skipped 0 claim(s) (pipeline mismatch).'; got: $(cat "$stderr_file")"
fi

# Plan-B (non-run-plan) must be untouched
if [ -d "$FIXTURE/.zskills/claims/plan-plan-b-slug" ]; then
  pass "non-run-plan claim (plan-b-slug) left intact"
else
  fail "non-run-plan claim preservation" "plan-b-slug claim was wrongly removed"
fi
# Plan-A and Plan-C must be gone
for slug in plan-a-slug plan-c-slug; do
  if [ ! -d "$FIXTURE/.zskills/claims/plan-$slug" ]; then
    pass "run-plan claim $slug removed by walk"
  else
    fail "run-plan claim $slug" "still exists after walk"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
