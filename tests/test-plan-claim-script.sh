#!/bin/bash
# tests/test-plan-claim-script.sh — Phase 1 W1.5.
#
# Unit tests for skills/run-plan/scripts/claim-plan.sh:
#   - acquire writes the 7-field D5 schema with sorted keys.
#   - refresh advances last_heartbeat_at + sets current_phase.
#   - refresh refuses on pipeline mismatch (exit 12, no mutation).
#   - refresh refuses on missing claim.json (exit 2).
#   - release removes the claim dir; idempotent on absent.
#   - release refuses on pipeline mismatch (exit 12).
#   - is-stale returns 0/1/2 per spec.
#   - is-stale crash-window 30s protection (claim dir without claim.json).
#   - sweep removes stale entries.
#   - list emits TSV.
#   - Concurrent refresh produces no partial JSON (parseable always).

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
    EXPECTED="current_phase,kind,last_heartbeat_at,pipeline_id,schema_version,slug,started_at"
    if [ "$KEYS" = "$EXPECTED" ]; then
      pass "acquire writes 7-field D5 schema (sorted keys)"
    else
      fail "acquire 7-field schema" "expected=$EXPECTED got=$KEYS"
    fi
    # Spot-check fields.
    KIND=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['kind'])")
    SLUG=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['slug'])")
    PIPE=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['pipeline_id'])")
    SCHEMA=$("$PYTHON" -c "import json; print(json.load(open('$CLAIM_FILE'))['schema_version'])")
    PHASE=$("$PYTHON" -c "import json; print(repr(json.load(open('$CLAIM_FILE'))['current_phase']))")
    if [ "$KIND" = "plan" ] && [ "$SLUG" = "foo" ] && [ "$PIPE" = "run-plan.foo" ] && [ "$SCHEMA" = "1" ] && [ "$PHASE" = "''" ]; then
      pass "acquire field values (kind=plan, slug=foo, schema_version=1, current_phase='')"
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
# 3. refresh advances last_heartbeat_at and sets current_phase.
# ───────────────────────────────────────────────────────────────────────
HB_BEFORE=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['last_heartbeat_at'])")
sleep 1
(
  cd "$REPO1"
  bash "$CLAIM_SH" refresh foo --require-pipeline "run-plan.foo" --current-phase "Phase 3"
)
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "refresh happy-path exit 0" "rc=$rc"
else
  HB_AFTER=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['last_heartbeat_at'])")
  CUR_PHASE=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['current_phase'])")
  if [ "$HB_BEFORE" != "$HB_AFTER" ] && [ "$CUR_PHASE" = "Phase 3" ]; then
    pass "refresh advances last_heartbeat_at and sets current_phase"
  else
    fail "refresh mutation" "hb_before=$HB_BEFORE hb_after=$HB_AFTER cur_phase=$CUR_PHASE"
  fi
  # started_at must be UNCHANGED.
  START_AFTER=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['started_at'])")
  START_BEFORE=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json.bak.notexist'))['started_at'])" 2>/dev/null || echo "")
  # We don't have a pre-image of started_at; instead assert it equals HB_BEFORE (which was the original heartbeat = started_at).
  if [ "$START_AFTER" = "$HB_BEFORE" ]; then
    pass "refresh does NOT mutate started_at"
  else
    fail "refresh started_at preserved" "after=$START_AFTER expected=$HB_BEFORE"
  fi
fi

# ───────────────────────────────────────────────────────────────────────
# 4. refresh refuses on pipeline mismatch (exit 12), no mutation.
# ───────────────────────────────────────────────────────────────────────
HB_BEFORE_MM=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['last_heartbeat_at'])")
PHASE_BEFORE_MM=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['current_phase'])")
(
  cd "$REPO1"
  bash "$CLAIM_SH" refresh foo --require-pipeline "run-plan.wrong" --current-phase "Phase 99"
) 2>/dev/null
rc=$?
HB_AFTER_MM=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['last_heartbeat_at'])")
PHASE_AFTER_MM=$("$PYTHON" -c "import json; print(json.load(open('$REPO1/.zskills/claims/plan-foo/claim.json'))['current_phase'])")
if [ "$rc" -eq 12 ] && [ "$HB_BEFORE_MM" = "$HB_AFTER_MM" ] && [ "$PHASE_BEFORE_MM" = "$PHASE_AFTER_MM" ]; then
  pass "refresh pipeline-mismatch returns 12 with no mutation"
else
  fail "refresh mismatch refusal" "rc=$rc hb_changed=$([ "$HB_BEFORE_MM" != "$HB_AFTER_MM" ] && echo yes || echo no) phase_changed=$([ "$PHASE_BEFORE_MM" != "$PHASE_AFTER_MM" ] && echo yes || echo no)"
fi

# ───────────────────────────────────────────────────────────────────────
# 5. refresh on missing claim returns exit 2.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" refresh nonexistent --require-pipeline "run-plan.nonexistent" --current-phase "Phase 1"
) 2>/dev/null
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "refresh on missing claim returns exit 2"
else
  fail "refresh missing exit 2" "got rc=$rc"
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
# 9. is-stale: no-claim => exit 2.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" is-stale gone
) 2>/dev/null
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "is-stale on no-claim returns exit 2"
else
  fail "is-stale no-claim exit 2" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# 10. is-stale: fresh claim => exit 1.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" acquire bar --pipeline-id "run-plan.bar"
  bash "$CLAIM_SH" is-stale bar
) 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "is-stale on fresh claim returns exit 1"
else
  fail "is-stale fresh exit 1" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# 11. is-stale: crash window — dir exists but no claim.json AND mtime > 30s
# ───────────────────────────────────────────────────────────────────────
CRASH_DIR="$REPO1/.zskills/claims/plan-crash"
mkdir -p "$CRASH_DIR"
# Backdate mtime by 60s.
"$PYTHON" -c "import os, time; os.utime('$CRASH_DIR', (time.time()-60, time.time()-60))"
(
  cd "$REPO1"
  bash "$CLAIM_SH" is-stale crash
) 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "is-stale crash-window (mtime > 30s, no claim.json) returns exit 0 (stale)"
else
  fail "is-stale crash-window" "got rc=$rc"
fi
rmdir "$CRASH_DIR" 2>/dev/null || true

# ───────────────────────────────────────────────────────────────────────
# 12. is-stale: TTL elapsed => exit 0.
# ───────────────────────────────────────────────────────────────────────
# Use a very low TTL via env override.
(
  cd "$REPO1"
  ZSKILLS_PLAN_CLAIM_TTL_SECONDS=60 bash "$CLAIM_SH" is-stale bar
) 2>/dev/null
rc_fresh=$?
# Now back-date the claim's last_heartbeat_at to 2h ago.
"$PYTHON" -c "
import json, datetime
fp='$REPO1/.zskills/claims/plan-bar/claim.json'
with open(fp) as f:
    d = json.load(f)
old = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=7300)).isoformat(timespec='seconds')
d['last_heartbeat_at'] = old
with open(fp, 'w') as f:
    json.dump(d, f, sort_keys=True)
"
(
  cd "$REPO1"
  bash "$CLAIM_SH" is-stale bar
) 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ] && [ "$rc_fresh" -eq 1 ]; then
  pass "is-stale TTL elapsed (>=7200s by default) returns exit 0 (stale)"
else
  fail "is-stale TTL elapsed" "fresh rc=$rc_fresh stale rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# 13. sweep removes stale entries.
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  bash "$CLAIM_SH" sweep
) 2>/dev/null
if [ ! -d "$REPO1/.zskills/claims/plan-bar" ]; then
  pass "sweep removes stale claim plan-bar"
else
  fail "sweep removes stale" "plan-bar still present"
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
# 15. concurrent refresh produces no partial JSON.
# Background 5 refreshes on a single claim; after wait, claim.json must
# always parse (os.replace is atomic, so this should hold).
# ───────────────────────────────────────────────────────────────────────
(
  cd "$REPO1"
  for i in 1 2 3 4 5; do
    bash "$CLAIM_SH" refresh baz --require-pipeline "run-plan.baz" --current-phase "Phase $i" &
  done
  wait
) 2>/dev/null
PARSE_OK=$("$PYTHON" -c "
import json
try:
    with open('$REPO1/.zskills/claims/plan-baz/claim.json') as f:
        d = json.load(f)
    assert d.get('kind') == 'plan'
    print('OK')
except Exception as e:
    print('ERR ' + str(e))
")
if [ "$PARSE_OK" = "OK" ]; then
  pass "concurrent refresh — claim.json parses cleanly (os.replace atomicity)"
else
  fail "concurrent refresh atomicity" "parse error: $PARSE_OK"
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
