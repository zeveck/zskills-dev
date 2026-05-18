#!/bin/bash
# Tests for skills/zskills-dashboard/scripts/zskills_monitor/collect.py
# (Phase 4 of plans/ZSKILLS_MONITOR_PLAN.md).
#
# Exercises the CLI, standalone-REPL importability, every fixture, and the
# error-cap / sort / cache invariants documented in the plan's Acceptance
# Criteria. Test output is captured into the per-worktree TEST_OUT path
# per CLAUDE.md (never piped).
#
# Run from repo root: bash tests/test_zskills_monitor_collect.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"
COLLECT_PY="$PKG_PARENT/zskills_monitor/collect.py"
FIXTURES="$REPO_ROOT/tests/fixtures/monitor"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not available — skipping all tests"
  skip "python3 not available"
  echo ""
  echo "---"
  printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" \
    "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
  exit 0
fi

if [ ! -f "$COLLECT_PY" ]; then
  fail "collect.py exists at expected path"
  printf 'Results: %d passed, %d failed, %d skipped\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  exit 1
fi

# ---------------------------------------------------------------------------
# AC: CLI exits 0 + top-level keys (minimal fixture)
# ---------------------------------------------------------------------------
echo "=== Phase 4 AC: CLI smoke + top-level keys ==="

run_collect() {
  # $1: fixture dir name under tests/fixtures/monitor
  PYTHONPATH="$PKG_PARENT" python3 -m zskills_monitor.collect \
    --fixture "$FIXTURES/$1"
}

OUT=$(run_collect minimal 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then
  pass "CLI --fixture minimal exits 0"
else
  fail "CLI --fixture minimal exits 0 (rc=$RC, output: $OUT)"
fi

EXPECTED_KEYS="activity branches errors issues issues_fetch_ok plans queues repo_root repo_url state_file_path state_updated_at updated_at version worktrees"
ACTUAL_KEYS=$(printf '%s' "$OUT" | python3 -c '
import json,sys
print(" ".join(sorted(json.load(sys.stdin).keys())))
')
if [ "$ACTUAL_KEYS" = "$EXPECTED_KEYS" ]; then
  pass "snapshot top-level keys exactly match contract"
else
  fail "snapshot top-level keys (got: $ACTUAL_KEYS)"
fi

# Per-plan minimum keys: slug, file, title, status, phases, category,
# meta_plan, sub_plans, queue.
PLAN_KEYS_OK=$(printf '%s' "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
required = {"slug","file","title","status","phases","category","meta_plan","sub_plans","queue"}
ok = all(required.issubset(p.keys()) for p in d["plans"])
print("OK" if ok else "MISSING")
')
if [ "$PLAN_KEYS_OK" = "OK" ]; then
  pass "each plan has required keys (slug,file,title,status,phases,category,meta_plan,sub_plans,queue)"
else
  fail "per-plan required keys missing"
fi

# ---------------------------------------------------------------------------
# AC: Standalone REPL importability + no-server grep
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: standalone REPL importability ==="

REPL_OUT=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import collect_snapshot, slug_of
snap = collect_snapshot("'"$FIXTURES/minimal"'")
print(",".join(sorted(snap.keys())))
print("slug=" + slug_of("MY_PLAN_FILE.md"))
' 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then
  pass "REPL: import + collect_snapshot returns dict (rc=0)"
else
  fail "REPL: collect_snapshot raised (rc=$RC, $REPL_OUT)"
fi
if printf '%s\n' "$REPL_OUT" | grep -q "slug=my-plan-file"; then
  pass "REPL: slug_of('MY_PLAN_FILE.md') == 'my-plan-file'"
else
  fail "REPL: slug_of result wrong ($REPL_OUT)"
fi

# Grep: no server-coupling imports.
if grep -nE 'from\s+\.server|from\s+zskills_monitor\.server|import\s+http\.server|import\s+socketserver' \
    "$COLLECT_PY" > /dev/null 2>&1; then
  fail "collect.py must not import server / http.server / socketserver"
else
  pass "collect.py has no server-coupling imports"
fi

# ---------------------------------------------------------------------------
# AC: No PyYAML / requests imports
# ---------------------------------------------------------------------------
if grep -nE '^import\s+(yaml|requests)' "$COLLECT_PY" > /dev/null 2>&1; then
  fail "collect.py imports yaml or requests"
else
  pass "collect.py has no PyYAML / requests imports"
fi

# ---------------------------------------------------------------------------
# AC: Briefing path-import (NOT bare `from scripts.briefing`)
# ---------------------------------------------------------------------------
if grep -nE '^from\s+scripts\.briefing\b' "$COLLECT_PY" > /dev/null 2>&1; then
  fail "collect.py uses bare 'from scripts.briefing' (forbidden post-Phase-B)"
else
  pass "collect.py does not use bare 'from scripts.briefing'"
fi
if grep -nE 'spec_from_file_location|sys\.path\.insert.+briefing' "$COLLECT_PY" > /dev/null 2>&1; then
  pass "collect.py uses path-based briefing import (spec_from_file_location)"
else
  fail "collect.py missing path-based briefing import"
fi

# ---------------------------------------------------------------------------
# AC: Category inference (canary / issue_tracker / executable+meta)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: category inference ==="

CAT_CANARY=$(run_collect category-canary | python3 -c '
import json,sys; d=json.load(sys.stdin); print(d["plans"][0]["category"])')
[ "$CAT_CANARY" = "canary" ] && pass "category-canary fixture → category=canary" \
  || fail "category-canary → got '$CAT_CANARY'"

CAT_ISSUES=$(run_collect category-issues | python3 -c '
import json,sys; d=json.load(sys.stdin); print(d["plans"][0]["category"])')
[ "$CAT_ISSUES" = "issue_tracker" ] && pass "category-issues fixture → category=issue_tracker" \
  || fail "category-issues → got '$CAT_ISSUES'"

CAT_META=$(run_collect category-meta | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
print(p["category"], p["meta_plan"], ",".join(p["sub_plans"]))')
if [ "$CAT_META" = "executable True sub" ]; then
  pass "category-meta fixture → category=executable, meta_plan=True, sub_plans=['sub']"
else
  fail "category-meta → got '$CAT_META'"
fi

# Cross-check: canary fixture's meta_plan should be False.
META_CANARY=$(run_collect category-canary | python3 -c '
import json,sys; d=json.load(sys.stdin); print(d["plans"][0]["meta_plan"])')
[ "$META_CANARY" = "False" ] && pass "category-canary meta_plan=False" \
  || fail "category-canary meta_plan should be False, got '$META_CANARY'"

# ---------------------------------------------------------------------------
# AC: Phase-heading separator coverage (issue #183)
# ---------------------------------------------------------------------------
# A plan whose phases use colon, en-dash, em-dash, or hyphen separators MUST
# be classified as executable with phase_count == 4. The pre-fix regex
# `[—-]` accepted only em-dash + hyphen, silently demoting colon-separated
# plans (the most common hand-authored form) to Reference. This test would
# have caught the original bug — pre-fix `phase_count` would be 1 (only the
# em-dash heading would match) and `category` would be `reference`.
echo ""
echo "=== Issue #183: phase-heading separator coverage ==="

SEP_OUT=$(run_collect phase-heading-separators)
SEP_RESULT=$(printf '%s' "$SEP_OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
p = d["plans"][0]
print(p["category"], p["phase_count"])
')
if [ "$SEP_RESULT" = "executable 4" ]; then
  pass "phase-heading-separators: em-dash/colon/en-dash/hyphen all match (category=executable, phase_count=4)"
else
  fail "phase-heading-separators: got '$SEP_RESULT' (expected 'executable 4')"
fi

# Direct regex unit test on the parser entry point — guards the regex even
# if categorize logic shifts in future.
SEP_PARSE=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import _parse_phase_headings
content = "## Phase 1 — Em-dash\n## Phase 2: Colon\n## Phase 3 – En-dash\n## Phase 4 - Hyphen\n"
phases = _parse_phase_headings(content)
print(",".join(p["n"] + "=" + p["name"] for p in phases))
')
if [ "$SEP_PARSE" = "1=Em-dash,2=Colon,3=En-dash,4=Hyphen" ]; then
  pass "_parse_phase_headings: all four separators (em-dash, colon, en-dash, hyphen) recognised"
else
  fail "_parse_phase_headings separator coverage: got '$SEP_PARSE'"
fi

# ---------------------------------------------------------------------------
# AC: Queue annotation (v1.1 ready/finish)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: queue annotation (v1.1) ==="

QUEUE_V11=$(run_collect with-state | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
print(p["slug"], p["queue"]["column"], p["queue"]["index"], p["queue"]["mode"])')
if [ "$QUEUE_V11" = "zskills-dashboard-plan ready 0 finish" ]; then
  pass "v1.1 state file → queue={column:ready,index:0,mode:finish}"
else
  fail "v1.1 queue annotation wrong: '$QUEUE_V11'"
fi

# ---------------------------------------------------------------------------
# AC: v1.0 compat (mode=null)
# ---------------------------------------------------------------------------
QUEUE_V10=$(run_collect state-v10 | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
mode = p["queue"]["mode"]
print(p["slug"], p["queue"]["column"], p["queue"]["index"], "null" if mode is None else mode)')
if [ "$QUEUE_V10" = "foo-plan ready 0 null" ]; then
  pass "v1.0 state file → queue.mode is null (flat-string array compat)"
else
  fail "v1.0 queue annotation wrong: '$QUEUE_V10'"
fi

# ---------------------------------------------------------------------------
# AC: Slug-rule parity vs Phase 1's inline `tr` rule
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: slug rule parity ==="

PY_SLUG=$(run_collect slug-uppercase | python3 -c '
import json,sys; d=json.load(sys.stdin); print(d["plans"][0]["slug"])')
TR_SLUG=$(printf '%s' "MY_PLAN_FILE" | tr '[:upper:]_' '[:lower:]-')
if [ "$PY_SLUG" = "$TR_SLUG" ] && [ "$PY_SLUG" = "my-plan-file" ]; then
  pass "Phase 4 slug_of() matches Phase 1 'tr' rule (both → my-plan-file)"
else
  fail "slug parity broken: py=$PY_SLUG, tr=$TR_SLUG"
fi

# ---------------------------------------------------------------------------
# AC: State-file absent — every plan has a default-inferred queue.column
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: state-file absent / corrupt ==="

NO_STATE_COL=$(run_collect minimal | python3 -c '
import json,sys
d=json.load(sys.stdin)
cols = {p["queue"]["column"] for p in d["plans"]}
# minimal has status=active + 0 phases done → drafted per Shared Schemas.
print(",".join(sorted(c if c is not None else "<None>" for c in cols)))')
if [ "$NO_STATE_COL" = "drafted" ]; then
  pass "state-file absent → plans default to inference column (drafted)"
else
  fail "state-absent default column wrong: '$NO_STATE_COL'"
fi

# ---------------------------------------------------------------------------
# AC: State-file corrupt — errors[] entry, no raise
# ---------------------------------------------------------------------------
CORRUPT_OUT=$(run_collect corrupt-state)
RC=$?
if [ "$RC" -eq 0 ]; then
  pass "corrupt-state fixture: collect runs without raising"
else
  fail "corrupt-state raised (rc=$RC)"
fi
CORRUPT_ERR=$(printf '%s' "$CORRUPT_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
hits=[e for e in d["errors"] if e["source"]==".zskills/monitor-state.json"]
print(len(hits), bool(hits and hits[0]["message"]))')
if [ "$CORRUPT_ERR" = "1 True" ]; then
  pass "corrupt-state: errors[] has 1 .zskills/monitor-state.json entry with non-empty message"
else
  fail "corrupt-state: errors[] wrong: '$CORRUPT_ERR'"
fi

# ---------------------------------------------------------------------------
# AC: snapshot.state_updated_at — propagates state file's `updated_at`
# (race-condition fix: applySnapshot stale-guard compares against the state
# file's authoritative timestamp, not snapshot composition time).
# ---------------------------------------------------------------------------
echo ""
echo "=== state_updated_at field propagation ==="

# Case 1: key always present in snapshot (minimal fixture: no state file)
HAS_KEY=$(run_collect minimal | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("state_updated_at" in d, repr(d.get("state_updated_at")))
')
if [ "$HAS_KEY" = "True ''" ]; then
  pass "state_updated_at present and empty when state file absent (minimal)"
else
  fail "state_updated_at missing/wrong for state-absent: '$HAS_KEY'"
fi

# Case 2: corrupt state file → state_updated_at is ""
CORRUPT_SUA=$(run_collect corrupt-state | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(repr(d.get("state_updated_at")))
')
if [ "$CORRUPT_SUA" = "''" ]; then
  pass "state_updated_at == '' when state file is corrupt"
else
  fail "state_updated_at wrong for corrupt-state: '$CORRUPT_SUA'"
fi

# Case 3: synthesize a fixture with a known updated_at and verify propagation.
SUA_PROP=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, sys, tempfile, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import collect_snapshot

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".zskills").mkdir()
state_doc = {
    "version": "1.1",
    "default_mode": "phase",
    "plans": {},
    "issues": {},
    "updated_at": "2026-05-17T07:00:00+00:00",
}
(tmp / ".zskills" / "monitor-state.json").write_text(json.dumps(state_doc))
snap = collect_snapshot(tmp, pre_resolved=True)
print(snap.get("state_updated_at"))
')
if [ "$SUA_PROP" = "2026-05-17T07:00:00+00:00" ]; then
  pass "state_updated_at propagates state file's updated_at verbatim"
else
  fail "state_updated_at propagation wrong: '$SUA_PROP'"
fi

# Case 4: state file without `updated_at` key → state_updated_at == ""
SUA_NO_KEY=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, sys, tempfile, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import collect_snapshot

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".zskills").mkdir()
state_doc = {
    "version": "1.1",
    "default_mode": "phase",
    "plans": {},
    "issues": {},
}
(tmp / ".zskills" / "monitor-state.json").write_text(json.dumps(state_doc))
snap = collect_snapshot(tmp, pre_resolved=True)
print(repr(snap.get("state_updated_at")))
')
if [ "$SUA_NO_KEY" = "''" ]; then
  pass "state_updated_at == '' when state file lacks updated_at key"
else
  fail "state_updated_at wrong when key absent: '$SUA_NO_KEY'"
fi

# ---------------------------------------------------------------------------
# AC: errors[] is sorted + deterministic across re-invocations
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: errors[] ordering + determinism ==="

DETERMINISM=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, json
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import _finalize_errors
errs = [
    {"source": "gh issue list",   "message": "x"},
    {"source": "briefing import", "message": "y"},
    {"source": "tracking marker", "message": "z"},
]
out1 = _finalize_errors(list(errs))
out2 = _finalize_errors(list(errs))
sorted_ok = [(e["source"], e["message"]) for e in out1] == \
    sorted([(e["source"], e["message"]) for e in errs])
byte_ok = json.dumps(out1) == json.dumps(out2)
print(f"sorted={sorted_ok} byte_id={byte_ok}")
')
if printf '%s\n' "$DETERMINISM" | grep -q "sorted=True byte_id=True"; then
  pass "errors[] sorted by (source,message) + byte-identical re-run"
else
  fail "errors[] determinism check failed: $DETERMINISM"
fi

# ---------------------------------------------------------------------------
# AC: errors[] cap at 100 + summary entry
# ---------------------------------------------------------------------------
CAP_OUT=$(run_collect error-cap)
CAP_LEN=$(printf '%s' "$CAP_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin); print(len(d["errors"]))')
CAP_HAS_SUMMARY=$(printf '%s' "$CAP_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
hits=[e for e in d["errors"] if e["source"]=="errors-cap"]
print(len(hits), bool(hits and hits[0]["message"]))')
if [ "$CAP_LEN" = "101" ] && [ "$CAP_HAS_SUMMARY" = "1 True" ]; then
  pass "error-cap fixture: 100 entries + 1 errors-cap summary (total 101)"
else
  fail "error-cap fail: len=$CAP_LEN summary=$CAP_HAS_SUMMARY"
fi

# ---------------------------------------------------------------------------
# AC: Landing-mode resolution (PR vs unknown sentinel)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: landing-mode resolution ==="

LAND_PR=$(run_collect landing-pr | python3 -c '
import json,sys; d=json.load(sys.stdin); print(d["plans"][0]["landing_mode"])')
[ "$LAND_PR" = "pr" ] && pass "landing-pr fixture → landing_mode=pr" \
  || fail "landing-pr got '$LAND_PR'"

LAND_UNK=$(run_collect landing-unknown | python3 -c '
import json,sys
d=json.load(sys.stdin)
p=d["plans"][0]
hits=[e for e in d["errors"] if e["source"]==".claude/zskills-config.json"]
print(p["landing_mode"], len(hits))')
if [ "$LAND_UNK" = "unknown 1" ]; then
  pass "landing-unknown fixture → landing_mode=unknown + config-source error"
else
  fail "landing-unknown got '$LAND_UNK'"
fi

# ---------------------------------------------------------------------------
# AC: Tracking dedup (subdir wins, conflict logged)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: tracking dedup ==="

DEDUP_OUT=$(run_collect tracking-dedup)
DEDUP_LEN=$(printf '%s' "$DEDUP_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin); print(len(d["activity"]))')
DEDUP_LOC=$(printf '%s' "$DEDUP_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(d["activity"][0]["location"], d["activity"][0]["pipeline"])')
DEDUP_OUTPUT=$(printf '%s' "$DEDUP_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin); print(d["activity"][0]["output"])')
DEDUP_ERR=$(printf '%s' "$DEDUP_OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
hits=[e for e in d["errors"] if e["source"]=="tracking dedup"]
print(len(hits))')
if [ "$DEDUP_LEN" = "1" ] && [ "$DEDUP_LOC" = "pipeline run-plan.x" ] \
    && [ "$DEDUP_OUTPUT" = "subdir copy (newer)" ] && [ "$DEDUP_ERR" = "1" ]; then
  pass "tracking dedup: 1 activity entry, subdir copy wins, errors[] logs conflict"
else
  fail "dedup wrong: len=$DEDUP_LEN loc=$DEDUP_LOC out='$DEDUP_OUTPUT' err=$DEDUP_ERR"
fi

# ---------------------------------------------------------------------------
# AC: Missing gh — issues=[] + errors[] entry, no exception
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: gh missing / failing ==="

GH_MISSING=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
c._reset_issue_cache_for_tests()
def boom(*a, **kw):
    raise FileNotFoundError("gh: not found")
errs = []
issues, ok = c.list_issues(errs, _now=1.0, _runner=boom)
print(len(issues), len(errs), errs[0]["source"] if errs else "", ok)
')
if [ "$GH_MISSING" = "0 1 gh issue list False" ]; then
  pass "missing gh: issues=[] + 'gh issue list' error + ok=False, no exception"
else
  fail "missing gh: got '$GH_MISSING'"
fi

# ---------------------------------------------------------------------------
# AC (issue #336): cold-start gh-list failure → snapshot.issues_fetch_ok=False
# AND queues block remains populated from state file (no client-side prune).
# Reproduces the cold-start window: empty issue cache + mocked gh failure
# + monitor-state.json with N issue entries → snapshot must carry the flag
# so the dashboard client preserves the user's ordering on the next POST.
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: cold-start gh-list failure (#336) ==="

COLD_START=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, sys, tempfile, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
c._reset_issue_cache_for_tests()

# Fixture: monitor-state.json with 3 queued issue numbers in "triage".
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".zskills").mkdir()
state_doc = {
    "version": "1.1",
    "default_mode": "phase",
    "plans": {},
    "issues": {"triage": [101, 202, 303]},
    "updated_at": "2026-05-18T00:00:00+00:00",
}
(tmp / ".zskills" / "monitor-state.json").write_text(json.dumps(state_doc))

# Mock gh issue list as a non-zero exit (transient failure on cold start).
class BoomResult:
    returncode = 1
    stdout = ""
    stderr = "gh: rate limit exceeded"
def runner(*a, **kw):
    return BoomResult()

snap = c.collect_snapshot(tmp, issue_runner=runner, pre_resolved=True)
print("issues_fetch_ok=" + repr(snap.get("issues_fetch_ok")))
print("issues_len=" + str(len(snap.get("issues", []))))
print("queue_triage=" + json.dumps(snap.get("queues", {}).get("issues", {}).get("triage", [])))
errs = [e for e in snap.get("errors", []) if e.get("source") == "gh issue list"]
print("error_reported=" + ("yes" if errs else "no"))
')
if printf '%s\n' "$COLD_START" | grep -q "^issues_fetch_ok=False$" \
    && printf '%s\n' "$COLD_START" | grep -q "^issues_len=0$" \
    && printf '%s\n' "$COLD_START" | grep -q "^queue_triage=\[101, 202, 303\]$" \
    && printf '%s\n' "$COLD_START" | grep -q "^error_reported=yes$"; then
  pass "cold-start gh failure: issues_fetch_ok=False + queues preserved + error logged (#336)"
else
  fail "cold-start gh failure (#336): got '$COLD_START'"
fi

# Steady-state mirror: successful gh fetch → issues_fetch_ok=True.
STEADY_OK=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, sys, tempfile, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
c._reset_issue_cache_for_tests()

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".zskills").mkdir()
(tmp / ".zskills" / "monitor-state.json").write_text(json.dumps({
    "version": "1.1", "default_mode": "phase",
    "plans": {}, "issues": {},
    "updated_at": "2026-05-18T00:00:00+00:00",
}))

class OkResult:
    returncode = 0
    stdout = "[]"
    stderr = ""
def runner(*a, **kw):
    return OkResult()

snap = c.collect_snapshot(tmp, issue_runner=runner, pre_resolved=True)
print(snap.get("issues_fetch_ok"))
')
if [ "$STEADY_OK" = "True" ]; then
  pass "steady-state gh success: issues_fetch_ok=True (#336)"
else
  fail "steady-state ok flag wrong: got '$STEADY_OK'"
fi

# ---------------------------------------------------------------------------
# AC: Missing/broken git — worktrees=[] + errors[]
# ---------------------------------------------------------------------------
GIT_MOCK=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
# Force briefing.classify_worktrees to raise.
class BoomBriefing:
    @staticmethod
    def classify_worktrees(repo_root=None):
        raise RuntimeError("git binary missing")
c._BRIEFING_MODULE = BoomBriefing
errs = []
wts = c._list_worktrees(pathlib.Path("'"$REPO_ROOT"'"), errs)
print(len(wts), errs[0]["source"] if errs else "NONE")
')
if printf '%s\n' "$GIT_MOCK" | grep -q "^0 git worktree$"; then
  pass "missing git (mocked classify_worktrees raise) → worktrees=[] + git-source error"
else
  fail "missing git mock: got '$GIT_MOCK'"
fi

# ---------------------------------------------------------------------------
# AC: Issue cache 60s TTL — second call within 60s does NOT re-invoke runner
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: issue cache TTL ==="

CACHE_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
c._reset_issue_cache_for_tests()

class FakeResult:
    returncode = 0
    stdout = "[]"
    stderr = ""
calls = []
def runner(*a, **kw):
    calls.append("X")
    return FakeResult()
errs = []
c.list_issues(errs, _now=100.0, _runner=runner)
c.list_issues(errs, _now=130.0, _runner=runner)  # 30s within TTL — cache hit
print(f"within_ttl_calls={len(calls)}")
c.list_issues(errs, _now=200.0, _runner=runner)  # 100s past TTL — re-fetch
print(f"after_ttl_calls={len(calls)}")
')
if printf '%s\n' "$CACHE_RES" | grep -q "within_ttl_calls=1" \
    && printf '%s\n' "$CACHE_RES" | grep -q "after_ttl_calls=2"; then
  pass "issue cache: 1 call within 60s; cache invalidated past 60s"
else
  fail "issue cache: got '$CACHE_RES'"
fi

# ---------------------------------------------------------------------------
# AC: Worktree-portable — collect from worktree matches collect from main
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 4 AC: worktree-portable repo_root resolution ==="

# Materialize a temp worktree on the fly so this case runs unconditionally,
# regardless of invocation context (primary repo, secondary worktree, fresh
# CI clone). The invariant being checked: collect_snapshot() resolves the
# MAIN_ROOT identically whether invoked from the primary checkout or any
# secondary worktree, so the stable subset (repo_root, plans, queues,
# state_file_path) is byte-identical across both contexts. Issue #150 fix —
# previously skipped silently when [ -f "$REPO_ROOT/.git" ] was false (i.e.,
# always in CI's actions/checkout@v4 primary clone), hiding the invariant.

TMP_WT="$(mktemp -d -t zskills-monitor-collect-wt-XXXXXX)"
# git worktree add needs a non-existing path
rmdir "$TMP_WT"
TMP_WT_CLEANED=0
cleanup_tmp_wt() {
  if [ "$TMP_WT_CLEANED" -eq 0 ] && [ -e "$TMP_WT" ]; then
    git -C "$REPO_ROOT" worktree remove --force "$TMP_WT" 2>/dev/null || rm -rf "$TMP_WT"
    TMP_WT_CLEANED=1
  fi
}
trap cleanup_tmp_wt EXIT

if git -C "$REPO_ROOT" worktree add --detach --quiet "$TMP_WT" HEAD 2>/dev/null; then
  PORTABLE=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, json
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import collect_snapshot

# Drop volatile keys (updated_at) and lists that depend on live env (issues
# from gh, activity timestamps not under our control). Compare the stable
# subset that worktree-portability protects: repo_root, plans, queues,
# state_file_path.
def stable(snap):
    return {
        "repo_root": snap["repo_root"],
        "plans": snap["plans"],
        "queues": snap["queues"],
        "state_file_path": snap["state_file_path"],
    }

s_a = stable(collect_snapshot("'"$REPO_ROOT"'"))
s_b = stable(collect_snapshot("'"$TMP_WT"'"))
print("repo_root_a=" + s_a["repo_root"])
print("repo_root_b=" + s_b["repo_root"])
print("byte_id=" + str(json.dumps(s_a, sort_keys=True) == json.dumps(s_b, sort_keys=True)))
')
  if printf '%s\n' "$PORTABLE" | grep -q "byte_id=True"; then
    pass "worktree-portable: stable snapshot subset is byte-identical from main vs worktree"
  else
    fail "worktree-portable: snapshots differ ($PORTABLE)"
  fi
  cleanup_tmp_wt
else
  fail "worktree-portable: could not materialize temp worktree at $TMP_WT"
  cleanup_tmp_wt
fi
trap - EXIT

# ---------------------------------------------------------------------------
# Issue #283: targeted coverage for activity helpers added in PR #274 + #277
# ---------------------------------------------------------------------------
# These tests exercise `_derive_repo_url`, `_scan_git_history`,
# `_extract_pr_numbers_from_markers`, and the dedup/cap/sort logic in
# `_collect_activity` directly via REPL imports (the fixtures don't carry
# a real `.git`, so these helpers no-op against fixtures).
echo ""
echo "=== Issue #283: dashboard activity-helper coverage ==="

# --- _derive_repo_url: regex unit cases ---------------------------------
# Drive the URL-translation logic via a stub that replaces git invocation
# with a hardcoded stdout. This exercises every branch of _GIT_HTTPS_RE,
# _GIT_SSH_RE, and the missing/empty-remote early-returns.
URL_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib, tempfile, subprocess
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

# We use a tmp dir with a stub .git so the existence guard passes; the
# git subprocess output is mocked via monkeypatch of subprocess.run.
tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".git").mkdir()

class FakeResult:
    def __init__(self, rc, stdout):
        self.returncode = rc
        self.stdout = stdout
        self.stderr = ""

cases = [
    # (remote-stdout, expected-derived-url, label)
    ("https://github.com/foo/bar.git",      "https://github.com/foo/bar", "https_with_dot_git"),
    ("https://github.com/foo/bar",          "https://github.com/foo/bar", "https_no_dot_git"),
    ("https://github.com/foo/bar/",         "https://github.com/foo/bar", "https_trailing_slash"),
    ("https://github.com/foo/bar.git/",     "https://github.com/foo/bar", "https_dot_git_trailing_slash"),
    ("http://gitea.local/foo/bar.git",      "https://gitea.local/foo/bar", "http_self_hosted"),
    ("git@github.com:foo/bar.git",          "https://github.com/foo/bar", "ssh_with_dot_git"),
    ("git@github.com:foo/bar",              "https://github.com/foo/bar", "ssh_no_dot_git"),
    ("git@gitlab.example.com:org/proj.git", "https://gitlab.example.com/org/proj", "ssh_custom_host"),
    ("ftp://nope.example/foo/bar",          "",                          "unknown_protocol"),
    ("",                                     "",                          "empty_remote_stdout"),
    ("not a url at all",                     "",                          "malformed_remote"),
]

results = []
for stdout, expected, label in cases:
    def fake_run(cmd, **kw):
        return FakeResult(0, stdout)
    orig = subprocess.run
    subprocess.run = fake_run
    try:
        got = c._derive_repo_url(tmp)
    finally:
        subprocess.run = orig
    ok = got == expected
    results.append((label, ok, expected, got))

# Missing-remote rc=1 path
def fake_run_rc1(cmd, **kw):
    return FakeResult(128, "")
orig = subprocess.run
subprocess.run = fake_run_rc1
try:
    got = c._derive_repo_url(tmp)
finally:
    subprocess.run = orig
results.append(("nonzero_rc_yields_empty", got == "", "", got))

# Missing `.git` dir entirely
tmp2 = pathlib.Path(tempfile.mkdtemp())
got = c._derive_repo_url(tmp2)
results.append(("no_git_dir_yields_empty", got == "", "", got))

# Timeout path
def fake_run_timeout(cmd, **kw):
    raise subprocess.TimeoutExpired(cmd, 2)
subprocess.run = fake_run_timeout
try:
    got = c._derive_repo_url(tmp)
finally:
    subprocess.run = orig
results.append(("timeout_yields_empty", got == "", "", got))

# OSError path (e.g., git binary missing)
def fake_run_oserror(cmd, **kw):
    raise OSError("git: not found")
subprocess.run = fake_run_oserror
try:
    got = c._derive_repo_url(tmp)
finally:
    subprocess.run = orig
results.append(("oserror_yields_empty", got == "", "", got))

bad = [r for r in results if not r[1]]
if bad:
    for label, _, exp, got in bad:
        print(f"FAIL {label}: expected={exp!r} got={got!r}")
    print("STATUS=BAD")
else:
    print(f"STATUS=OK count={len(results)}")
')
if printf '%s\n' "$URL_RES" | grep -q "^STATUS=OK"; then
  N=$(printf '%s\n' "$URL_RES" | grep -oE "count=[0-9]+" | cut -d= -f2)
  pass "_derive_repo_url: all ${N} URL forms (SSH/HTTPS/.git/trailing/empty/rc!=0/timeout/OSError) translate correctly"
else
  fail "_derive_repo_url: at least one case wrong: $URL_RES"
fi

# --- _scan_git_history: real-git fixture --------------------------------
# Build a real throwaway git repo with deliberately tricky commit subjects
# so we exercise the regex anchors directly. The fixtures dir is read-only
# (no .git), so we materialize a tmpdir for this case.
HIST_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib, tempfile, subprocess, json
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

tmp = pathlib.Path(tempfile.mkdtemp())
def git(*args):
    subprocess.run(["git", "-C", str(tmp), *args], check=True,
                   capture_output=True, text=True,
                   env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
                        "PATH": "/usr/bin:/bin:/usr/local/bin"})
git("init", "--quiet", "-b", "main")
git("commit", "--allow-empty", "-m", "fix: trailing PR ref (#100)")
git("commit", "--allow-empty", "-m", "docs: inline body ref (#999) and trailer (#101)")
git("commit", "--allow-empty", "-m", "chore: closes #200 with no PR trailer")
git("commit", "--allow-empty", "-m", "feat(scope): subject with no refs at all")
git("commit", "--allow-empty", "-m", "fix: ref #300 followed by PR trailer (#102)")
# This commit also gets dedup-skipped (its trailing (#101) is in fulfilled_prs).

errors = []
rows = c._scan_git_history(tmp, errors, since_hours=720, max_commits=200,
                           fulfilled_pr_numbers={"101"})

if errors:
    print("ERRORS:", errors)
# Index by subject suffix for clarity
by_sub = {r["subject"]: r for r in rows}

checks = []
# (#100) trailer extracted
r = by_sub.get("fix: trailing PR ref (#100)")
checks.append(("trailer_extracted", r is not None and r["pr"] == "100" and r["issue"] == ""))
# (#101) trailer commit should be DROPPED via dedup
checks.append(("dedup_drops_101", "docs: inline body ref (#999) and trailer (#101)" not in by_sub))
# closes #200 — issue extracted, pr empty
r = by_sub.get("chore: closes #200 with no PR trailer")
checks.append(("issue_only_no_pr", r is not None and r["pr"] == "" and r["issue"] == "200"))
# bare subject — both empty
r = by_sub.get("feat(scope): subject with no refs at all")
checks.append(("bare_subject_empty", r is not None and r["pr"] == "" and r["issue"] == ""))
# inline #300 + trailer (#102) — pr=102, issue=300 (different group)
r = by_sub.get("fix: ref #300 followed by PR trailer (#102)")
checks.append(("inline_plus_trailer", r is not None and r["pr"] == "102" and r["issue"] == "300"))
# shape: every record has location=git, kind=commit, sha set, id=sha[:7]
shape_ok = all(r["location"] == "git" and r["kind"] == "commit"
               and len(r["sha"]) >= 7 and r["id"] == r["sha"][:7] for r in rows)
checks.append(("record_shape", shape_ok))
# timestamp is ISO-8601 (contains T) on every row
ts_ok = all("T" in r["timestamp"] for r in rows)
checks.append(("timestamp_iso", ts_ok))

# Edge: empty repo
tmp2 = pathlib.Path(tempfile.mkdtemp())
subprocess.run(["git", "-C", str(tmp2), "init", "--quiet", "-b", "main"], check=True,
               capture_output=True, text=True)
errs2 = []
rows2 = c._scan_git_history(tmp2, errs2, since_hours=720, max_commits=200)
checks.append(("empty_repo_yields_empty", rows2 == [] and errs2 == []))

# Edge: no .git at all
tmp3 = pathlib.Path(tempfile.mkdtemp())
errs3 = []
rows3 = c._scan_git_history(tmp3, errs3, since_hours=720, max_commits=200)
checks.append(("no_git_yields_empty", rows3 == [] and errs3 == []))

# Edge: malformed git log output (mock subprocess to return non-\x1f data)
class FakeResult:
    returncode = 0
    stdout = "this is\nnot the\nright format\n"
    stderr = ""
orig = subprocess.run
def fake_run(cmd, **kw):
    return FakeResult()
subprocess.run = fake_run
try:
    errs4 = []
    rows4 = c._scan_git_history(tmp, errs4, since_hours=720, max_commits=200)
finally:
    subprocess.run = orig
checks.append(("malformed_lines_dropped", rows4 == [] and errs4 == []))

bad = [name for name, ok in checks if not ok]
if bad:
    for r in rows:
        print("  row:", repr(r.get("subject")), "pr=", repr(r.get("pr")), "issue=", repr(r.get("issue")))
    print("FAILED:", bad)
else:
    print("STATUS=OK count=" + str(len(checks)))
' 2>&1)
if printf '%s\n' "$HIST_RES" | grep -q "^STATUS=OK"; then
  N=$(printf '%s\n' "$HIST_RES" | grep -oE "count=[0-9]+" | cut -d= -f2)
  pass "_scan_git_history: ${N} cases (trailer/inline/dedup/empty/no-git/malformed/shape)"
else
  fail "_scan_git_history: $HIST_RES"
fi

# --- _extract_pr_numbers_from_markers: real marker dir ------------------
PR_MARKER_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib, tempfile
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

root = pathlib.Path(tempfile.mkdtemp())
tr = root / ".zskills" / "tracking"
tr.mkdir(parents=True)

# Case 1: flat marker with a github.com PR URL
(tr / "fulfilled.land-pr.aaa").write_text(
    "skill: land-pr\nstatus: complete\ndate: 2026-05-01T00:00:00-04:00\n"
    "pr: https://github.com/foo/bar/pull/100\n",
    encoding="utf-8",
)
# Case 2: subdir marker with a different PR URL
(tr / "pipe1").mkdir()
(tr / "pipe1" / "fulfilled.land-pr.bbb").write_text(
    "skill: land-pr\nstatus: complete\ndate: 2026-05-02T00:00:00-04:00\n"
    "pr: https://github.com/foo/bar/pull/200\n",
    encoding="utf-8",
)
# Case 3: marker with NO pr field — must not crash, contributes nothing
(tr / "fulfilled.land-pr.ccc").write_text(
    "skill: land-pr\nstatus: complete\ndate: 2026-05-03T00:00:00-04:00\n",
    encoding="utf-8",
)
# Case 4: marker that is NOT a land-pr kind — must be ignored
(tr / "fulfilled.run-plan.xxx").write_text(
    "skill: run-plan\nstatus: complete\ndate: 2026-05-04T00:00:00-04:00\n"
    "pr: https://github.com/foo/bar/pull/999\n",
    encoding="utf-8",
)
# Case 5: pr field that is plain text not a URL — must be ignored
(tr / "fulfilled.land-pr.ddd").write_text(
    "skill: land-pr\nstatus: complete\ndate: 2026-05-05T00:00:00-04:00\n"
    "pr: just some text without a URL\n",
    encoding="utf-8",
)

nums = c._extract_pr_numbers_from_markers(root)
print("nums=" + ",".join(sorted(nums)))

# Edge: tracking dir missing entirely
root2 = pathlib.Path(tempfile.mkdtemp())
nums2 = c._extract_pr_numbers_from_markers(root2)
print("missing_dir=" + str(nums2 == set()))

# Edge: tracking is a file, not a dir
root3 = pathlib.Path(tempfile.mkdtemp())
(root3 / ".zskills").mkdir()
(root3 / ".zskills" / "tracking").write_text("oops", encoding="utf-8")
nums3 = c._extract_pr_numbers_from_markers(root3)
print("tracking_is_file=" + str(nums3 == set()))
' 2>&1)
if printf '%s\n' "$PR_MARKER_RES" | grep -q "^nums=100,200$" \
    && printf '%s\n' "$PR_MARKER_RES" | grep -q "^missing_dir=True$" \
    && printf '%s\n' "$PR_MARKER_RES" | grep -q "^tracking_is_file=True$"; then
  pass "_extract_pr_numbers_from_markers: collects flat+subdir PR URLs, ignores non-land-pr kinds + missing fields + non-URL pr text + missing tracking dir"
else
  fail "_extract_pr_numbers_from_markers: $PR_MARKER_RES"
fi

# --- Dedup integration: marker-PR vs history (#N) trailer ---------------
# Construct one real git repo + tracking dir, then run _scan_git_history
# with fulfilled_prs computed via _extract_pr_numbers_from_markers. The
# commit whose trailer matches the marker MUST be dropped from history.
DEDUP_INT_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib, tempfile, subprocess
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

root = pathlib.Path(tempfile.mkdtemp())
env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
       "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
       "PATH": "/usr/bin:/bin:/usr/local/bin"}
def git(*args):
    subprocess.run(["git", "-C", str(root), *args], check=True,
                   capture_output=True, text=True, env=env)
git("init", "--quiet", "-b", "main")
git("commit", "--allow-empty", "-m", "fix: tracked (#500)")    # has marker — drop
git("commit", "--allow-empty", "-m", "feat: untracked (#501)")  # no marker — keep
git("commit", "--allow-empty", "-m", "docs: nothing trailing")  # no PR ref — keep

# Marker dir referencing only PR 500.
tr = root / ".zskills" / "tracking"
tr.mkdir(parents=True)
(tr / "fulfilled.land-pr.x").write_text(
    "skill: land-pr\nstatus: complete\ndate: 2026-05-10T00:00:00-04:00\n"
    "pr: https://github.com/foo/bar/pull/500\n",
    encoding="utf-8",
)

fulfilled = c._extract_pr_numbers_from_markers(root)
errs = []
rows = c._scan_git_history(root, errs, since_hours=720, max_commits=200,
                           fulfilled_pr_numbers=fulfilled)
subjects = sorted(r["subject"] for r in rows)
prs = sorted(r["pr"] for r in rows if r["pr"])
print("subjects=" + "|".join(subjects))
print("prs=" + ",".join(prs))
print("fulfilled=" + ",".join(sorted(fulfilled)))
' 2>&1)
if printf '%s\n' "$DEDUP_INT_RES" | grep -q "^fulfilled=500$" \
    && printf '%s\n' "$DEDUP_INT_RES" | grep -q "^prs=501$" \
    && printf '%s\n' "$DEDUP_INT_RES" | grep -q "docs: nothing trailing" \
    && printf '%s\n' "$DEDUP_INT_RES" | grep -q "feat: untracked" \
    && ! printf '%s\n' "$DEDUP_INT_RES" | grep -q "fix: tracked"; then
  pass "history+marker dedup: commit whose (#N) trailer matches a fulfilled.land-pr.* marker is dropped"
else
  fail "history+marker dedup: $DEDUP_INT_RES"
fi

# --- collect_snapshot activity sort + cap-at-200 ------------------------
# Build a marker dir of 250 markers; resulting activity must be sorted
# descending by timestamp and capped at 200.
CAP_SORT_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib, tempfile
sys.path.insert(0, "'"$PKG_PARENT"'")
from zskills_monitor.collect import collect_snapshot

root = pathlib.Path(tempfile.mkdtemp())
tr = root / ".zskills" / "tracking"
tr.mkdir(parents=True)
# 250 markers; ids 0..249. Older ids get older timestamps, so the top-200
# should be ids 50..249.
for i in range(250):
    ts = f"2026-01-01T00:00:{i:02d}-04:00" if i < 60 else f"2026-01-01T{(i//60):02d}:{(i%60):02d}:00-04:00"
    (tr / f"fulfilled.run-plan.id{i:03d}").write_text(
        f"skill: run-plan\nstatus: complete\ndate: {ts}\noutput: row{i:03d}\n",
        encoding="utf-8",
    )

# We also drop a plans dir to keep the snapshot well-formed.
(root / "plans").mkdir()

snap = collect_snapshot(root)
activity = snap["activity"]
print("len=" + str(len(activity)))
# Sorted desc → first ts must be the LARGEST one.
ts_list = [a["timestamp"] for a in activity]
print("sorted_desc=" + str(ts_list == sorted(ts_list, reverse=True)))
# Top entry should be id249 (latest).
print("top_id=" + activity[0]["id"])
' 2>&1)
if printf '%s\n' "$CAP_SORT_RES" | grep -q "^len=200$" \
    && printf '%s\n' "$CAP_SORT_RES" | grep -q "^sorted_desc=True$" \
    && printf '%s\n' "$CAP_SORT_RES" | grep -q "^top_id=run-plan.id249$"; then
  pass "_collect_activity: cap-at-200 + sort-desc-by-timestamp invariants hold"
else
  fail "_collect_activity cap/sort: $CAP_SORT_RES"
fi

# --- Dead-arg cleanup: _extract_pr_numbers_from_markers signature -------
# Per issue #283 bonus: the obsolete `activity` parameter must be gone.
SIG_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, inspect
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
sig = inspect.signature(c._extract_pr_numbers_from_markers)
params = list(sig.parameters.keys())
print("params=" + ",".join(params))
')
if [ "$SIG_RES" = "params=main_root" ]; then
  pass "_extract_pr_numbers_from_markers signature is (main_root,) — dead 'activity' arg removed"
else
  fail "_extract_pr_numbers_from_markers signature wrong: $SIG_RES"
fi

# ---------------------------------------------------------------------------
# AC: Test registered in tests/run-all.sh (verified by the test runner if
# we're invoked via run-all.sh; here we just sanity-check this file is
# referenced).
# ---------------------------------------------------------------------------
if grep -q "test_zskills_monitor_collect.sh" "$REPO_ROOT/tests/run-all.sh" 2>/dev/null; then
  pass "tests/run-all.sh references test_zskills_monitor_collect.sh"
else
  fail "tests/run-all.sh missing test_zskills_monitor_collect.sh registration"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 1
fi
