#!/bin/bash
# tests/test-plan-claim-script.sh — Phase 1 W1.5.
#
# Unit tests for skills/run-plan/scripts/claim-plan.sh:
#   - acquire writes the 7-field D5 schema with sorted keys.
#   - acquire EEXIST on duplicate slug returns exit 10.
#   - release removes the claim dir; idempotent on absent.
#   - release refuses on pipeline mismatch (exit 12).
#   - list emits TSV.
#   - Usage / slug-sanitisation errors return exit 2.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-plan-claim-script-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  echo "FATAL: no Python interpreter available" >&2
  exit 1
fi

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# Make claim-plan.sh discoverable: copy sanitize-pipeline-id.sh into the
# expected sibling layout inside SCRATCH so the script's _locate_sanitizer
# finds it. We do this by symlinking the source tree's create-worktree
# scripts dir adjacent to the test's run-plan/scripts layout via a fake
# CLAUDE_PROJECT_DIR pointing back at REPO_ROOT (the sanitizer lives in
# REPO_ROOT/skills/create-worktree/scripts/).
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

echo "=== claim-plan.sh unit tests ==="

# ───────────────────────────────────────────────────────────────────────
# 1. acquire writes the 7-field D5 schema.
# ───────────────────────────────────────────────────────────────────────
REPO1="$SCRATCH_ROOT/r1"
make_repo "$REPO1" || { echo "FATAL repo init"; exit 1; }
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire foo --pipeline-id "run-plan.foo"
)
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "acquire happy-path exit 0" "rc=$rc"
else
  CLAIM_FILE="$REPO1/.zskills/claims/plan-foo/claim.json"
  if [ ! -f "$CLAIM_FILE" ]; then
    fail "acquire writes claim.json" "file missing at $CLAIM_FILE"
  else
    KEYS=$("$PYTHON" -c "
import json
d=json.load(open('$CLAIM_FILE'))
print(','.join(sorted(d.keys())))
")
    EXPECTED="current_phase,kind,pipeline_id,schema_version,slug,started_at"
    if [ "$KEYS" = "$EXPECTED" ]; then
      pass "acquire writes 6-field D5 schema (sorted keys)"
    else
      fail "acquire 6-field schema" "expected=$EXPECTED got=$KEYS"
    fi
    # Spot-check fields.
    KIND=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['kind'])")
    SLUG=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['slug'])")
    PIPE=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['pipeline_id'])")
    SCHEMA=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['schema_version'])")
    PHASE=$("$PYTHON" -c "import json; print(repr(json.load(open('$CLAIM_FILE'))['current_phase']))")
    EXPECTED_PHASE="'Phase 0 — acquired'"
    if [ "$KIND" = "plan" ] && [ "$SLUG" = "foo" ] && [ "$PIPE" = "run-plan.foo" ] && [ "$SCHEMA" = "1" ] && [ "$PHASE" = "$EXPECTED_PHASE" ]; then
      pass "acquire field values (kind=plan, slug=foo, schema_version=1, current_phase='Phase 0 — acquired')"
    else
      fail "acquire field values" "kind=$KIND slug=$SLUG pipe=$PIPE schema=$SCHEMA phase=$PHASE"
    fi
  fi
fi

# ───────────────────────────────────────────────────────────────────────
# 2. Duplicate acquire returns exit 10.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire foo --pipeline-id "run-plan.foo-dup"
)
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "duplicate acquire returns exit 10 (EEXIST)"
else
  fail "duplicate acquire exit 10" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# 6. release refuses on pipeline mismatch (exit 12).
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" release foo --require-pipeline "run-plan.wrong"
) 2>/dev/null
rc=$?
if [ "$rc" -eq 12 ] && [ -d "$REPO1/.zskills/claims/plan-foo" ]; then
  pass "release pipeline-mismatch returns 12 with claim intact"
else
  fail "release mismatch refusal" "rc=$rc dir_present=$([ -d "$REPO1/.zskills/claims/plan-foo" ] && echo yes || echo no)"
fi

# ───────────────────────────────────────────────────────────────────────
# 7. release happy-path removes claim dir.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" release foo --require-pipeline "run-plan.foo"
)
rc=$?
if [ "$rc" -eq 0 ] && [ ! -d "$REPO1/.zskills/claims/plan-foo" ]; then
  pass "release happy-path removes claim dir"
else
  fail "release happy-path" "rc=$rc dir_present=$([ -d "$REPO1/.zskills/claims/plan-foo" ] && echo yes || echo no)"
fi

# ───────────────────────────────────────────────────────────────────────
# 8. release idempotent on absent.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" release foo --require-pipeline "run-plan.foo"
)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "release idempotent on absent (rc=0)"
else
  fail "release idempotent" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# 14. list emits TSV for live claims.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire baz --pipeline-id "run-plan.baz"
  bash "$CLAIM_SH" acquire qux --pipeline-id "run-plan.qux"
) 2>/dev/null
LIST_OUT=$(cd "$REPO1" && bash "$CLAIM_SH" list 2>/dev/null | sort)
LINE_COUNT=$(echo "$LIST_OUT" | wc -l)
FIRST_LINE=$(echo "$LIST_OUT" | head -1)
# Should be 2 lines, each TSV with 3 fields.
TSV_FIELDS=$(echo "$FIRST_LINE" | awk -F'\t' '{print NF}')
if [ "$LINE_COUNT" -eq 2 ] && [ "$TSV_FIELDS" = "3" ]; then
  pass "list emits 2 TSV lines with 3 tab-separated fields"
else
  fail "list TSV shape" "lines=$LINE_COUNT first_line_fields=$TSV_FIELDS out=<$LIST_OUT>"
fi

# ───────────────────────────────────────────────────────────────────────
# 16. usage errors return exit 2.
# ───────────────────────────────────────────────────────────────────────
(cd "$REPO1" && bash "$CLAIM_SH" acquire) 2>/dev/null
rc1=$?
(cd "$REPO1" && bash "$CLAIM_SH" acquire foo) 2>/dev/null  # missing --pipeline-id
rc2=$?
(cd "$REPO1" && bash "$CLAIM_SH") 2>/dev/null
rc3=$?
(cd "$REPO1" && bash "$CLAIM_SH" bogus-sub) 2>/dev/null
rc4=$?
if [ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ "$rc3" -eq 2 ] && [ "$rc4" -eq 2 ]; then
  pass "usage errors return exit 2 (missing slug, missing --pipeline-id, missing sub, bogus sub)"
else
  fail "usage exit 2" "rc1=$rc1 rc2=$rc2 rc3=$rc3 rc4=$rc4"
fi

# ───────────────────────────────────────────────────────────────────────
# 17. slug sanitisation: invalid slugs (uppercase, underscores, leading dash)
# return exit 2.
# ───────────────────────────────────────────────────────────────────────
(cd "$REPO1" && bash "$CLAIM_SH" acquire FOO --pipeline-id "run-plan.foo") 2>/dev/null
rc_upper=$?
(cd "$REPO1" && bash "$CLAIM_SH" acquire "_bad" --pipeline-id "run-plan.bad") 2>/dev/null
rc_under=$?
(cd "$REPO1" && bash "$CLAIM_SH" acquire "-bad" --pipeline-id "run-plan.bad") 2>/dev/null
rc_dash=$?
if [ "$rc_upper" -eq 2 ] && [ "$rc_under" -eq 2 ] && [ "$rc_dash" -eq 2 ]; then
  pass "slug sanitisation rejects uppercase / underscore / leading-dash with exit 2"
else
  fail "slug sanitisation" "upper=$rc_upper under=$rc_under dash=$rc_dash"
fi

# ───────────────────────────────────────────────────────────────────────
# 18. set-phase: happy path mutates current_phase atomically.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire setphase --pipeline-id "run-plan.setphase"
) 2>/dev/null
SETPHASE_FILE="$REPO1/.zskills/claims/plan-setphase/claim.json"
(cd "$REPO1" && bash "$CLAIM_SH" set-phase setphase --require-pipeline "run-plan.setphase" --current-phase "Phase 3 — verified") 2>/dev/null
rc_sp_ok=$?
NEW_PHASE=$("$PYTHON" -c "import json; print(json.load(open('$SETPHASE_FILE'))['current_phase'])")
if [ "$rc_sp_ok" -eq 0 ] && [ "$NEW_PHASE" = "Phase 3 — verified" ]; then
  pass "set-phase happy path: rc=0, current_phase updated"
else
  fail "set-phase happy path" "rc=$rc_sp_ok new_phase=<$NEW_PHASE>"
fi
# Verify pipeline_id and other fields were preserved.
PRESERVED_PIPE=$("$PYTHON" -c "import json; print(json.load(open('$SETPHASE_FILE'))['pipeline_id'])")
PRESERVED_KIND=$("$PYTHON" -c "import json; print(json.load(open('$SETPHASE_FILE'))['kind'])")
if [ "$PRESERVED_PIPE" = "run-plan.setphase" ] && [ "$PRESERVED_KIND" = "plan" ]; then
  pass "set-phase preserves pipeline_id and other fields"
else
  fail "set-phase preservation" "pipe=$PRESERVED_PIPE kind=$PRESERVED_KIND"
fi

# ───────────────────────────────────────────────────────────────────────
# 19. set-phase: pipeline mismatch returns exit 12, no mutation.
# ───────────────────────────────────────────────────────────────────────
(cd "$REPO1" && bash "$CLAIM_SH" set-phase setphase --require-pipeline "run-plan.WRONG" --current-phase "Phase 9 — bogus") 2>/dev/null
rc_sp_mismatch=$?
AFTER_MISMATCH=$("$PYTHON" -c "import json; print(json.load(open('$SETPHASE_FILE'))['current_phase'])")
if [ "$rc_sp_mismatch" -eq 12 ] && [ "$AFTER_MISMATCH" = "Phase 3 — verified" ]; then
  pass "set-phase pipeline mismatch: rc=12, no mutation"
else
  fail "set-phase pipeline mismatch" "rc=$rc_sp_mismatch after=<$AFTER_MISMATCH>"
fi

# ───────────────────────────────────────────────────────────────────────
# 20. set-phase: missing claim returns exit 2.
# ───────────────────────────────────────────────────────────────────────
(cd "$REPO1" && bash "$CLAIM_SH" set-phase nonexistent --require-pipeline "run-plan.anything" --current-phase "Phase 1") 2>/dev/null
rc_sp_missing=$?
if [ "$rc_sp_missing" -eq 2 ]; then
  pass "set-phase missing claim: rc=2"
else
  fail "set-phase missing claim" "rc=$rc_sp_missing"
fi

# ───────────────────────────────────────────────────────────────────────
# 21. --dispatch-mode "finish" persists dispatch_mode="finish" on claim.json (#874).
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire dmfinish --pipeline-id "run-plan.dmfinish" --dispatch-mode finish
) 2>/dev/null
DM_FILE="$REPO1/.zskills/claims/plan-dmfinish/claim.json"
if [ -f "$DM_FILE" ]; then
  DM_VAL=$("$PYTHON" -c "import json; print(json.load(open('$DM_FILE')).get('dispatch_mode','<absent>'))")
  if [ "$DM_VAL" = "finish" ]; then
    pass "--dispatch-mode finish persists dispatch_mode='finish' (#874)"
  else
    fail "--dispatch-mode finish persists" "got dispatch_mode=<$DM_VAL>"
  fi
else
  fail "--dispatch-mode finish acquire" "claim.json missing"
fi

# ───────────────────────────────────────────────────────────────────────
# 22. --dispatch-mode "phase" persists dispatch_mode="phase" on claim.json.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire dmphase --pipeline-id "run-plan.dmphase" --dispatch-mode phase
) 2>/dev/null
DMP_FILE="$REPO1/.zskills/claims/plan-dmphase/claim.json"
if [ -f "$DMP_FILE" ]; then
  DMP_VAL=$("$PYTHON" -c "import json; print(json.load(open('$DMP_FILE')).get('dispatch_mode','<absent>'))")
  if [ "$DMP_VAL" = "phase" ]; then
    pass "--dispatch-mode phase persists dispatch_mode='phase'"
  else
    fail "--dispatch-mode phase persists" "got dispatch_mode=<$DMP_VAL>"
  fi
fi

# ───────────────────────────────────────────────────────────────────────
# 23. --dispatch-mode "inherit" is a no-op (field omitted from claim.json).
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire dminherit --pipeline-id "run-plan.dminherit" --dispatch-mode inherit
) 2>/dev/null
DMI_FILE="$REPO1/.zskills/claims/plan-dminherit/claim.json"
if [ -f "$DMI_FILE" ]; then
  DMI_HAS=$("$PYTHON" -c "import json; d=json.load(open('$DMI_FILE')); print('yes' if 'dispatch_mode' in d else 'no')")
  if [ "$DMI_HAS" = "no" ]; then
    pass "--dispatch-mode inherit omits dispatch_mode field (back-compat)"
  else
    fail "--dispatch-mode inherit omits" "dispatch_mode present in claim.json"
  fi
fi

# ───────────────────────────────────────────────────────────────────────
# 24. Flag absent: dispatch_mode field omitted (pre-#874 schema).
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire dmabsent --pipeline-id "run-plan.dmabsent"
) 2>/dev/null
DMA_FILE="$REPO1/.zskills/claims/plan-dmabsent/claim.json"
if [ -f "$DMA_FILE" ]; then
  DMA_HAS=$("$PYTHON" -c "import json; d=json.load(open('$DMA_FILE')); print('yes' if 'dispatch_mode' in d else 'no')")
  if [ "$DMA_HAS" = "no" ]; then
    pass "flag absent: dispatch_mode field omitted (pre-#874 schema unchanged)"
  else
    fail "flag absent omits" "dispatch_mode present in claim.json"
  fi
fi

# ───────────────────────────────────────────────────────────────────────
# 25. Invalid --dispatch-mode value returns exit 2.
# ───────────────────────────────────────────────────────────────────────
(cd "$REPO1" && bash "$CLAIM_SH" acquire dmbogus --pipeline-id "run-plan.dmbogus" --dispatch-mode bogus) 2>/dev/null
rc_bogus=$?
if [ "$rc_bogus" -eq 2 ] && [ ! -d "$REPO1/.zskills/claims/plan-dmbogus" ]; then
  pass "--dispatch-mode bogus returns exit 2 (usage error, no claim created)"
else
  fail "--dispatch-mode bogus exit 2" "rc=$rc_bogus dir=$([ -d "$REPO1/.zskills/claims/plan-dmbogus" ] && echo yes || echo no)"
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
