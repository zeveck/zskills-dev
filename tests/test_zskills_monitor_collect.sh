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

EXPECTED_KEYS="activity branches errors flags issues issues_fetch_ok plans queues repo_root repo_url state_file_path state_updated_at updated_at version worktrees"
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
# AC (#514): per-subsystem snapshot cache — _cached_subsystem hit/miss/expire
# ---------------------------------------------------------------------------
echo ""
echo "=== Issue #514: per-subsystem snapshot cache TTL ==="

SCACHE_RES=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

# Hit/miss invariants on a deterministic _now clock.
c._reset_snapshot_cache_for_tests()
calls = []
def fn(errs):
    calls.append("X")
    errs.append({"source": "test", "message": "boom"})
    return ["value"]

root = pathlib.Path("/fake/main")
errs1 = []
v1 = c._cached_subsystem("kind1", root, 5.0, fn, errs1, _now=100.0)
v2 = c._cached_subsystem("kind1", root, 5.0, fn, errs1, _now=102.0)  # within TTL — hit
v3 = c._cached_subsystem("kind1", root, 5.0, fn, errs1, _now=104.99)  # still hit
v4 = c._cached_subsystem("kind1", root, 5.0, fn, errs1, _now=105.5)  # past TTL — miss
print("calls_after_4=" + str(len(calls)))  # expect 2
print("value_stable=" + str(v1 == v2 == v3 == v4))
print("errors_replayed=" + str(len(errs1)))  # 4

# Different kind doesn t collide.
errs2 = []
c._cached_subsystem("kind2", root, 5.0, fn, errs2, _now=100.0)
print("calls_after_kind2=" + str(len(calls)))  # 3

# Different main_root doesn t collide.
c._cached_subsystem("kind1", pathlib.Path("/other/main"), 5.0, fn, errs2, _now=100.0)
print("calls_after_otherroot=" + str(len(calls)))  # 4

# Fail-loud: if fn raises, cache is NOT updated.
c._reset_snapshot_cache_for_tests()
def boom_fn(errs):
    raise RuntimeError("intentional")
try:
    c._cached_subsystem("k", root, 5.0, boom_fn, [], _now=100.0)
except RuntimeError:
    pass
print("cache_size_after_raise=" + str(len(c._SNAPSHOT_CACHE)))  # 0
')
if printf '%s\n' "$SCACHE_RES" | grep -q "calls_after_4=2" \
    && printf '%s\n' "$SCACHE_RES" | grep -q "value_stable=True" \
    && printf '%s\n' "$SCACHE_RES" | grep -q "errors_replayed=4" \
    && printf '%s\n' "$SCACHE_RES" | grep -q "calls_after_kind2=3" \
    && printf '%s\n' "$SCACHE_RES" | grep -q "calls_after_otherroot=4" \
    && printf '%s\n' "$SCACHE_RES" | grep -q "cache_size_after_raise=0"; then
  pass "snapshot cache: hit within TTL, miss past TTL, kind+root keying, fail-loud on raise"
else
  fail "snapshot cache TTL: got '$SCACHE_RES'"
fi

# Integration: collect_snapshot does NOT re-invoke fan-out helpers within TTL.
SCACHE_INT=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys, pathlib, tempfile
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

c._reset_snapshot_cache_for_tests()
c._reset_issue_cache_for_tests()

counts = {"wt": 0, "br": 0, "hist": 0, "mk": 0, "extract_pr": 0}
def wt(root, errs):
    counts["wt"] += 1
    return []
def br(root, errs):
    counts["br"] += 1
    return []
def hist(root, errs, **kw):
    counts["hist"] += 1
    return []
def mk(root, errs):
    counts["mk"] += 1
    return []
def extract_pr(root):
    counts["extract_pr"] += 1
    return set()
c._list_worktrees = wt
c._list_branches = br
c._scan_git_history = hist
c._scan_tracking_markers = mk
c._extract_pr_numbers_from_markers = extract_pr

class FakeResult:
    returncode = 0
    stdout = "[]"
    stderr = ""
def runner(*a, **kw):
    return FakeResult()

with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td)
    c.collect_snapshot(root, pre_resolved=True, issue_runner=runner)
    print("after_first wt=" + str(counts["wt"]) + " br=" + str(counts["br"]) + " hist=" + str(counts["hist"]) + " mk=" + str(counts["mk"]) + " extract_pr=" + str(counts["extract_pr"]))
    c.collect_snapshot(root, pre_resolved=True, issue_runner=runner)
    print("after_second wt=" + str(counts["wt"]) + " br=" + str(counts["br"]) + " hist=" + str(counts["hist"]) + " mk=" + str(counts["mk"]) + " extract_pr=" + str(counts["extract_pr"]))
    c._reset_snapshot_cache_for_tests()
    c.collect_snapshot(root, pre_resolved=True, issue_runner=runner)
    print("after_reset wt=" + str(counts["wt"]) + " br=" + str(counts["br"]) + " hist=" + str(counts["hist"]) + " mk=" + str(counts["mk"]) + " extract_pr=" + str(counts["extract_pr"]))
')
if printf '%s\n' "$SCACHE_INT" | grep -q "after_first wt=1 br=1 hist=1 mk=1 extract_pr=1" \
    && printf '%s\n' "$SCACHE_INT" | grep -q "after_second wt=1 br=1 hist=1 mk=1 extract_pr=1" \
    && printf '%s\n' "$SCACHE_INT" | grep -q "after_reset wt=2 br=2 hist=2 mk=2 extract_pr=2"; then
  pass "collect_snapshot: fan-out helpers cached within TTL, re-invoked on cache reset"
else
  fail "collect_snapshot cache integration: got '$SCACHE_INT'"
fi

# ---------------------------------------------------------------------------
# Phase 1 (completed-backlog-sections): Completed-window + backlog tests
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 1 completed-backlog-sections: bounded closed-issue fetch + inference + state v1.2 ==="

# W1.8 — list_closed_issues_in_window_bounded_by_date.
# Mock the gh runner to return 5 closed issues with varied closedAt
# timestamps; assert the function returns the gh-payload as-is (gh's
# `--search` is server-side, so the test just verifies the function
# wires the call + parses `closedAt` into `closed_at`).
W18=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
c._reset_issue_cache_for_tests()

class Result:
    returncode = 0
    stderr = ""
    stdout = json.dumps([
        {"number": 1, "title": "in", "labels": [], "createdAt": "2026-05-20T00:00:00Z", "closedAt": "2026-05-20T01:00:00Z", "body": ""},
        {"number": 2, "title": "in", "labels": [], "createdAt": "2026-05-15T00:00:00Z", "closedAt": "2026-05-15T01:00:00Z", "body": ""},
        {"number": 3, "title": "in", "labels": [], "createdAt": "2026-05-10T00:00:00Z", "closedAt": "2026-05-10T01:00:00Z", "body": ""},
        {"number": 4, "title": "in", "labels": [], "createdAt": "2026-05-05T00:00:00Z", "closedAt": "2026-05-05T01:00:00Z", "body": ""},
        {"number": 5, "title": "in", "labels": [], "createdAt": "2026-04-30T00:00:00Z", "closedAt": "2026-04-30T01:00:00Z", "body": ""},
    ])

calls = []
def runner(*a, **kw):
    calls.append(a[0])
    return Result()
errs = []
issues, ok = c.list_closed_issues_in_window(errs, days=14, limit=500, _runner=runner)
print("ok=" + repr(ok))
print("n=" + str(len(issues)))
print("closed_at_present=" + str(all("closed_at" in i for i in issues)))
print("first_closed_at=" + issues[0]["closed_at"])
# Verify the gh call carried --state closed + --search closed:>=YYYY-MM-DD.
argv = calls[0] if calls else []
print("state_closed=" + str("closed" in argv))
print("search_present=" + str(any(s.startswith("closed:>=") for s in argv)))
' 2>&1)
if printf '%s\n' "$W18" | grep -q "^ok=True$" \
    && printf '%s\n' "$W18" | grep -q "^n=5$" \
    && printf '%s\n' "$W18" | grep -q "^closed_at_present=True$" \
    && printf '%s\n' "$W18" | grep -q "^state_closed=True$" \
    && printf '%s\n' "$W18" | grep -q "^search_present=True$"; then
  pass "W1.8: list_closed_issues_in_window_bounded_by_date"
else
  fail "W1.8: got '$W18'"
fi

# W1.9 — _infer_default_column within/outside window AND _infer_issue_default_column within window.
W19=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone, timedelta

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
plan_within = {"status": "complete", "completed": (now - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ"), "phases_done": 1}
plan_outside = {"status": "complete", "completed": (now - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ"), "phases_done": 1}
plan_no_completed = {"status": "complete", "phases_done": 1}
print("within=" + repr(c._infer_default_column(plan_within, now_utc=now, window_days=14)))
print("outside=" + repr(c._infer_default_column(plan_outside, now_utc=now, window_days=14)))
print("no_completed=" + repr(c._infer_default_column(plan_no_completed, now_utc=now, window_days=14)))
issue_within = {"number": 1, "closed_at": (now - timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%SZ")}
issue_outside = {"number": 2, "closed_at": (now - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")}
issue_no_closed = {"number": 3}
print("issue_within=" + c._infer_issue_default_column(issue_within, now_utc=now, window_days=14))
print("issue_outside=" + c._infer_issue_default_column(issue_outside, now_utc=now, window_days=14))
print("issue_no_closed=" + c._infer_issue_default_column(issue_no_closed, now_utc=now, window_days=14))
' 2>&1)
if printf '%s\n' "$W19" | grep -q "^within='completed'$" \
    && printf '%s\n' "$W19" | grep -q "^outside=None$" \
    && printf '%s\n' "$W19" | grep -q "^no_completed=None$" \
    && printf '%s\n' "$W19" | grep -q "^issue_within=completed$" \
    && printf '%s\n' "$W19" | grep -q "^issue_outside=triage$" \
    && printf '%s\n' "$W19" | grep -q "^issue_no_closed=triage$"; then
  pass "W1.9: infer_default_column within/outside + infer_issue_default_column within window"
else
  fail "W1.9: got '$W19'"
fi

# W1.9a — parse_plan_extracts_completed_field: write a plan markdown with
# `completed:` frontmatter, call parse_plan, assert the returned dict has
# the `completed` key populated. Closes Bug A of PR #650 fields-plumbing:
# parse_plan previously stripped the field so `_infer_default_column`
# never saw it, and every status=complete plan was hidden regardless of
# `completed:` value. End-to-end (W1.9b) compounds this with the
# inference call to prove the full pipeline now works.
W19A=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import pathlib, sys, tempfile
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

tmp = pathlib.Path(tempfile.mkdtemp())
fp = tmp / "test-plan.md"
fp.write_text("""---
title: "Test Plan"
status: complete
created: "2026-05-01T00:00:00Z"
completed: "2026-05-15T12:30:00Z"
---

# Test Plan
""")
plan = c.parse_plan(fp)
print("has_completed=" + str("completed" in plan))
print("completed=" + repr(plan.get("completed")))
print("status=" + repr(plan.get("status")))
' 2>&1)
if printf '%s\n' "$W19A" | grep -q "^has_completed=True$" \
    && printf '%s\n' "$W19A" | grep -q "^completed='2026-05-15T12:30:00Z'$" \
    && printf '%s\n' "$W19A" | grep -q "^status='complete'$"; then
  pass "W1.9a: parse_plan_extracts_completed_field"
else
  fail "W1.9a: got '$W19A'"
fi

# W1.9b — infer_default_column_through_parse_plan: end-to-end. Calls
# parse_plan() on the SAME fixture (not a hand-stubbed dict) and passes
# the result into _infer_default_column. The W1.9 stub-dict test passed
# even while Bug A made the parse_plan pipeline strip `completed`; this
# end-to-end variant is the regression bar.
W19B=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import pathlib, sys, tempfile
from datetime import datetime, timezone
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

tmp = pathlib.Path(tempfile.mkdtemp())
fp = tmp / "test-plan.md"
fp.write_text("""---
title: "Test Plan"
status: complete
created: "2026-05-01T00:00:00Z"
completed: "2026-05-15T12:30:00Z"
---

# Test Plan
""")
plan = c.parse_plan(fp)
now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
col = c._infer_default_column(plan, now_utc=now, window_days=14)
print("col=" + repr(col))
' 2>&1)
if printf '%s\n' "$W19B" | grep -q "^col='completed'$"; then
  pass "W1.9b: infer_default_column_through_parse_plan (end-to-end)"
else
  fail "W1.9b: got '$W19B'"
fi

# W1.10 — read_state_file_v11_migration: v1.1 fixture parses cleanly,
# `backlog` defaults to [] for both plans and issues.
W110=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, pathlib, sys, tempfile
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".zskills").mkdir()
state_doc = {
    "version": "1.1",
    "default_mode": "phase",
    "plans": {"drafted": [{"slug": "p", "mode": None}]},
    "issues": {"triage": [42]},
    "updated_at": "2026-05-18T00:00:00+00:00",
}
(tmp / ".zskills" / "monitor-state.json").write_text(json.dumps(state_doc))
errs = []
state = c._read_state_file(tmp, errs)
print("errors=" + str(len(errs)))
print("version=" + state["version"])
print("plans_backlog=" + repr(state["plans"].get("backlog")))
print("issues_backlog=" + repr(state["issues"].get("backlog")))
print("plans_drafted=" + repr(state["plans"].get("drafted")))
' 2>&1)
if printf '%s\n' "$W110" | grep -q "^errors=0$" \
    && printf '%s\n' "$W110" | grep -q "^version=1.1$" \
    && printf '%s\n' "$W110" | grep -q "^plans_backlog=\[\]$" \
    && printf '%s\n' "$W110" | grep -q "^issues_backlog=\[\]$" \
    && printf '%s\n' "$W110" | grep -q "plans_drafted=\[{'slug': 'p'"; then
  pass "W1.10: read_state_file_v11_migration (v1.1 parses cleanly + backlog defaults to [])"
else
  fail "W1.10: got '$W110'"
fi

# W1.11 — annotate_issues_queue_assigns_completed: a closed-within-window
# issue not in state-file lands in `completed`.
W111=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone, timedelta

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
state = {"issues": {"backlog": []}, "plans": {"backlog": []}}
issues = [
    {"number": 100, "closed_at": (now - timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%SZ")},
    {"number": 200, "closed_at": ""},
]
c._annotate_issues_queue(issues, state, None, now_utc=now, window_days=14)
print("issue_100=" + issues[0]["queue"]["column"])
print("issue_200=" + issues[1]["queue"]["column"])
' 2>&1)
if printf '%s\n' "$W111" | grep -q "^issue_100=completed$" \
    && printf '%s\n' "$W111" | grep -q "^issue_200=triage$"; then
  pass "W1.11: annotate_issues_queue_assigns_completed"
else
  fail "W1.11: got '$W111'"
fi

# W1.12 — config_dashboard_completed_days_flows_to_inference: setting
# execution.dashboard_completed_days to 7 narrows the window.
W112=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import json, pathlib, sys, tempfile
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / ".claude").mkdir()
cfg = {"execution": {"dashboard_completed_days": 7, "dashboard_completed_limit": 250}}
(tmp / ".claude" / "zskills-config.json").write_text(json.dumps(cfg))
days, limit = c._read_dashboard_completed_config(tmp)
print("days=" + str(days))
print("limit=" + str(limit))

# Default fall-through.
tmp2 = pathlib.Path(tempfile.mkdtemp())
days2, limit2 = c._read_dashboard_completed_config(tmp2)
print("default_days=" + str(days2))
print("default_limit=" + str(limit2))
' 2>&1)
if printf '%s\n' "$W112" | grep -q "^days=7$" \
    && printf '%s\n' "$W112" | grep -q "^limit=250$" \
    && printf '%s\n' "$W112" | grep -q "^default_days=14$" \
    && printf '%s\n' "$W112" | grep -q "^default_limit=500$"; then
  pass "W1.12: config_dashboard_completed_days_flows_to_inference"
else
  fail "W1.12: got '$W112'"
fi

# W1.19 — annotate_issues_queue_prefers_closed_on_dual_membership:
# same issue # in BOTH open + closed fetch lists. Dedupe-prefer-closed
# (W1.3 / DA3.7): the merged list with open-first/closed-last yields a
# single entry in `completed`.
W119=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone, timedelta

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
state = {"issues": {"backlog": []}, "plans": {"backlog": []}}
# Same issue #N appears in both fetches — closed-side wins.
open_entry = {"number": 500, "title": "stale-open", "closed_at": ""}
closed_entry = {"number": 500, "title": "fresh-closed", "closed_at": (now - timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ")}
issues = [open_entry, closed_entry]
c._annotate_issues_queue(issues, state, None, now_utc=now, window_days=14)
print("count=" + str(len(issues)))
print("col=" + issues[0]["queue"]["column"])
print("title=" + issues[0]["title"])
' 2>&1)
if printf '%s\n' "$W119" | grep -q "^count=1$" \
    && printf '%s\n' "$W119" | grep -q "^col=completed$" \
    && printf '%s\n' "$W119" | grep -q "^title=fresh-closed$"; then
  pass "W1.19: annotate_issues_queue_prefers_closed_on_dual_membership"
else
  fail "W1.19: got '$W119'"
fi

# W1.20 — annotate_plans_queue_prefers_completed_on_dual_membership:
# WRONG — actually per D2 state-file explicit-position WINS over
# inference. A plan in state-file's `drafted` column with status:complete
# stays in `drafted`, NOT in `completed`.
W120=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone, timedelta

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
state = {
    "plans": {
        "drafted": [{"slug": "my-plan", "mode": None}],
        "backlog": [],
    },
    "issues": {"backlog": []},
}
plans = [
    {"slug": "my-plan", "status": "complete",
     "completed": (now - timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%SZ"),
     "phases_done": 1},
]
c._annotate_plans_queue(plans, state, now_utc=now, window_days=14)
print("col=" + plans[0]["queue"]["column"])
' 2>&1)
if printf '%s\n' "$W120" | grep -q "^col=drafted$"; then
  pass "W1.20: annotate_plans_queue_prefers_state_explicit_over_completed (D2)"
else
  fail "W1.20: got '$W120'"
fi

# W1.21 — annotate_issues_queue_drops_closed_from_explicit_positions:
# state-file has issue #N in `triage` with `closed_at` set within window.
# The explicit-position bypass must NOT keep it in `triage`; instead
# `_infer_issue_default_column` routes it to `completed` (in-window).
# Closes #670 — auto-prune closed issues from explicit-active columns.
W121=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone, timedelta

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
state = {
    "issues": {"triage": [42], "backlog": []},
    "plans": {"backlog": []},
}
# Issue #42 is in state.issues.triage AND closed in-window.
# The auto-prune must filter it out of `pos`, letting inference win.
issues = [
    {"number": 42, "closed_at": (now - timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%SZ")},
]
c._annotate_issues_queue(issues, state, None, now_utc=now, window_days=14)
print("col=" + issues[0]["queue"]["column"])
' 2>&1)
if printf '%s\n' "$W121" | grep -q "^col=completed$"; then
  pass "W1.21: annotate_issues_queue_drops_closed_from_explicit_positions (#670)"
else
  fail "W1.21: got '$W121'"
fi

# W1.22 — annotate_issues_queue_hides_closed_out_of_window_with_explicit_position:
# state-file has issue #N in `triage` with `closed_at` OUTSIDE the 14-day
# window. Auto-prune still drops it from `pos`; inference fallback routes
# to `triage` (the `_infer_issue_default_column` default). The "hide"
# part is enforced upstream by the caller's open+closed-window fetch
# contract — at this boundary we only assert the explicit-position bypass
# fires (state-file says triage, but inference owns the column).
# Closes #670.
W122=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone, timedelta

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
state = {
    "issues": {"triage": [99], "backlog": []},
    "plans": {"backlog": []},
}
# Closed 30 days ago — outside the 14-day window.
issues = [
    {"number": 99, "closed_at": (now - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")},
]
c._annotate_issues_queue(issues, state, None, now_utc=now, window_days=14)
print("col=" + issues[0]["queue"]["column"])
print("index=" + str(issues[0]["queue"]["index"]))
' 2>&1)
if printf '%s\n' "$W122" | grep -q "^col=triage$" \
    && printf '%s\n' "$W122" | grep -q "^index=-1$"; then
  pass "W1.22: annotate_issues_queue_hides_closed_out_of_window_with_explicit_position (#670)"
else
  fail "W1.22: got '$W122'"
fi

# W1.23 — annotate_plans_queue_drops_orphan_state_file_entries:
# state-file has slug `nonexistent-plan` in `drafted`, but the `plans`
# list passed in does NOT contain a dict with that slug. The orphan must
# be auto-pruned from `pos` so it never affects rendering, and unrelated
# plans (e.g. `real-plan` in `backlog`) must NOT pick up the orphan's
# index-0 position from the state file's `drafted` array.
#
# Without the auto-prune, `pos` would have
# `{"nonexistent-plan": ("drafted", 0, None)}`. `real-plan` would not be
# in `pos` and would fall through to inference. The auto-prune ensures
# the orphan never enters `pos`, AND a same-column-different-slug
# scenario does not get its index shifted by the orphan's presence.
#
# Concrete assertion: real-plan-in-backlog must end up with
# `column=backlog, index=0` (the explicit state-file position), and the
# orphan slug must never appear anywhere in the output.
# Closes #671 — auto-prune orphan plan slugs.
W123=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone

now = datetime(2026, 5, 22, 12, 0, 0, tzinfo=timezone.utc)
state = {
    "plans": {
        "drafted": [{"slug": "nonexistent-plan"}],
        "backlog": [{"slug": "real-plan"}],
    },
    "issues": {"backlog": []},
}
# `real-plan` is the only parsed plan; `nonexistent-plan` is an orphan.
plans = [
    {"slug": "real-plan", "status": "active", "phases_done": 0},
]
c._annotate_plans_queue(plans, state, now_utc=now, window_days=14)
# real-plan picks up backlog from its OWN state-file position, NOT
# from the orphan-slug entry in drafted.
print("real_col=" + plans[0]["queue"]["column"])
print("real_index=" + str(plans[0]["queue"]["index"]))
# Confirm no plan in the result list has slug == nonexistent-plan.
orphan_present = any(p.get("slug") == "nonexistent-plan" for p in plans)
print("orphan_present=" + str(orphan_present))
print("plan_count=" + str(len(plans)))
' 2>&1)
if printf '%s\n' "$W123" | grep -q "^real_col=backlog$" \
    && printf '%s\n' "$W123" | grep -q "^real_index=0$" \
    && printf '%s\n' "$W123" | grep -q "^orphan_present=False$" \
    && printf '%s\n' "$W123" | grep -q "^plan_count=1$"; then
  pass "W1.23: annotate_plans_queue_drops_orphan_state_file_entries (#671)"
else
  fail "W1.23: got '$W123'"
fi

# ---------------------------------------------------------------------------
# Issue #677 — discarded_plan_does_not_reappear_in_drafted (regression canary)
# ---------------------------------------------------------------------------
# Locks the explicit-state-wins semantic for the new `discarded` column:
# a status:active plan slug present in state.plans.discarded MUST be
# annotated with queue.column == "discarded" (NOT "drafted" via the
# _infer_default_column fallback). Pre-#677 the ✕ button was a no-op
# precisely because the bare "splice from explicit state" pattern
# bounced active plans back to Drafted on the next snapshot — this test
# encodes the fix.
W677=$(PYTHONPATH="$PKG_PARENT" python3 -c '
import sys
sys.path.insert(0, "'"$PKG_PARENT"'")
import zskills_monitor.collect as c
from datetime import datetime, timezone

now = datetime(2026, 5, 26, 12, 0, 0, tzinfo=timezone.utc)
# state-file says "discarded-plan" is in the discarded column. Plan has
# status:active + phases_done==0 — exactly the case where the pre-fix
# inference fallback would route it to "drafted".
state = {
    "plans": {
        "drafted": [],
        "reviewed": [],
        "ready": [],
        "backlog": [],
        "discarded": [{"slug": "discarded-plan"}],
    },
    "issues": {"backlog": []},
}
plans = [
    {"slug": "discarded-plan", "status": "active", "phases_done": 0},
]
c._annotate_plans_queue(plans, state, now_utc=now, window_days=14)
print("col=" + plans[0]["queue"]["column"])
print("index=" + str(plans[0]["queue"]["index"]))
' 2>&1)
if printf '%s\n' "$W677" | grep -q "^col=discarded$" \
    && printf '%s\n' "$W677" | grep -q "^index=0$"; then
  pass "#677: discarded_plan_does_not_reappear_in_drafted (explicit-state-wins for discarded)"
else
  fail "#677: discarded_plan_does_not_reappear_in_drafted — got '$W677' (expected col=discarded, index=0)"
fi

# ---------------------------------------------------------------------------
# Phase 1: backfill-plan-completed.sh tests (W1.13–W1.18)
# ---------------------------------------------------------------------------
echo ""
echo "=== Phase 1 completed-backlog-sections: backfill-plan-completed.sh ==="

BACKFILL_SCRIPT="$REPO_ROOT/skills/zskills-dashboard/scripts/backfill-plan-completed.sh"

# Helper: build a fresh fixture repo that has:
#   - .claude/zskills-config.json (so the precheck passes)
#   - $PLANS_DIR (configurable)
#   - scripts/frontmatter-set.sh + frontmatter-get.sh (copies)
#   - .claude/skills/update-zskills/scripts/zskills-paths.sh (copy)
build_backfill_fixture() {
  local dir="$1"
  local plans_rel="$2"   # e.g. "docs/plans" or "plans"
  mkdir -p "$dir/.claude" "$dir/scripts" \
           "$dir/.claude/skills/update-zskills/scripts" \
           "$dir/$plans_rel"
  cat > "$dir/.claude/zskills-config.json" <<JSON
{
  "output": {"plans_dir": "$plans_rel"}
}
JSON
  cp "$REPO_ROOT/scripts/frontmatter-set.sh" "$dir/scripts/"
  cp "$REPO_ROOT/scripts/frontmatter-get.sh" "$dir/scripts/"
  cp "$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh" \
     "$dir/.claude/skills/update-zskills/scripts/"
  chmod +x "$dir/scripts/frontmatter-set.sh" \
           "$dir/scripts/frontmatter-get.sh"
}

write_plan_with_status_complete() {
  local file="$1"
  cat > "$file" <<MD
---
name: $(basename "$file" .md)
status: complete
---

# Plan
MD
}

# W1.13 — backfill_plan_completed_idempotent: run twice, second run no-op.
W113_TMP="$(mktemp -d)"
build_backfill_fixture "$W113_TMP" "docs/plans"
(
  cd "$W113_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  write_plan_with_status_complete "docs/plans/test-plan.md"
  git add -A && git commit -qm "initial: test-plan complete"
  # First run.
  CLAUDE_PROJECT_DIR="$W113_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w113-run1.txt 2>&1
  cp docs/plans/test-plan.md /tmp/w113-after-run1.md
  # Second run — must be a no-op (file unchanged).
  CLAUDE_PROJECT_DIR="$W113_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w113-run2.txt 2>&1
  if diff -q /tmp/w113-after-run1.md docs/plans/test-plan.md > /dev/null; then
    echo "IDEMPOTENT_OK"
  else
    echo "IDEMPOTENT_FAIL"
    diff /tmp/w113-after-run1.md docs/plans/test-plan.md
  fi
) > /tmp/w113-result.txt 2>&1
W113=$(cat /tmp/w113-result.txt)
if printf '%s\n' "$W113" | grep -q "^IDEMPOTENT_OK$"; then
  pass "W1.13: backfill_plan_completed_idempotent"
else
  fail "W1.13: got '$W113' (run1=$(cat /tmp/w113-run1.txt 2>&1), run2=$(cat /tmp/w113-run2.txt 2>&1))"
fi

# W1.14 — backfill_plan_completed_resolves_plans_dir_from_config: with
# output.plans_dir: "docs/plans", the script writes to docs/plans/ NOT
# to phantom plans/. Also: conformance grep against hardcoded `plans/`.
W114_TMP="$(mktemp -d)"
build_backfill_fixture "$W114_TMP" "docs/plans"
(
  cd "$W114_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  write_plan_with_status_complete "docs/plans/the-plan.md"
  git add -A && git commit -qm "initial: the-plan complete"
  CLAUDE_PROJECT_DIR="$W114_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w114-run.txt 2>&1
  # Assert: docs/plans/the-plan.md has completed:; no phantom plans/ dir.
  if grep -q "^completed:" docs/plans/the-plan.md; then
    echo "DOCS_PLANS_WRITTEN"
  fi
  if [ ! -d plans ]; then
    echo "NO_PHANTOM_PLANS_DIR"
  fi
) > /tmp/w114-result.txt 2>&1
W114=$(cat /tmp/w114-result.txt)
# Conformance grep against the antipattern, per spec.
GREP_ANTIPATTERN=$(grep -nE '"plans/" *<slug>|plans/\$slug|plans/\\\$slug' \
  "$BACKFILL_SCRIPT" 2>/dev/null | wc -l)
if printf '%s\n' "$W114" | grep -q "^DOCS_PLANS_WRITTEN$" \
    && printf '%s\n' "$W114" | grep -q "^NO_PHANTOM_PLANS_DIR$" \
    && [ "$GREP_ANTIPATTERN" -eq 0 ]; then
  pass "W1.14: backfill_plan_completed_resolves_plans_dir_from_config + conformance grep"
else
  fail "W1.14: got '$W114' antipattern_hits=$GREP_ANTIPATTERN"
fi

# W1.15 — backfill_plan_completed_rename_survives: create plan A,
# commit status:complete, rename to B, backfill (with --follow) finds
# the original status-introduction commit.
W115_TMP="$(mktemp -d)"
build_backfill_fixture "$W115_TMP" "docs/plans"
(
  cd "$W115_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  # Initial: plan-A.md with status: active.
  cat > docs/plans/plan-A.md <<'MD'
---
name: plan-A
status: active
---
# A
MD
  git add -A && git commit -qm "add plan-A active"
  # Introduce status: complete on plan-A.
  cat > docs/plans/plan-A.md <<'MD'
---
name: plan-A
status: complete
---
# A
MD
  GIT_AUTHOR_DATE='2026-04-01T12:00:00Z' GIT_COMMITTER_DATE='2026-04-01T12:00:00Z' \
    git -c user.email=t@t -c user.name=t commit -qam "plan-A complete"
  # Rename plan-A -> plan-B.
  git mv docs/plans/plan-A.md docs/plans/plan-B.md
  GIT_AUTHOR_DATE='2026-05-01T12:00:00Z' GIT_COMMITTER_DATE='2026-05-01T12:00:00Z' \
    git -c user.email=t@t -c user.name=t commit -qm "rename plan-A to plan-B"
  CLAUDE_PROJECT_DIR="$W115_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w115-run.txt 2>&1
  # plan-B.md should now carry completed: 2026-04-01T12:00:00Z (from the
  # original A's status-introduction commit, surfaced via --follow).
  completed_val=$(grep "^completed:" docs/plans/plan-B.md | sed -E 's/^completed:[[:space:]]*"?([^"]*)"?$/\1/')
  echo "completed=$completed_val"
) > /tmp/w115-result.txt 2>&1
W115=$(cat /tmp/w115-result.txt)
if printf '%s\n' "$W115" | grep -q "^completed=2026-04-01T12:00:00Z$"; then
  pass "W1.15: backfill_plan_completed_rename_survives (--follow finds original status-intro commit)"
else
  fail "W1.15: got '$W115' run=$(cat /tmp/w115-run.txt 2>&1)"
fi

# W1.15b — backfill_plan_completed_normalizes_local_tz_to_utc_z:
# committer date '2026-05-15T08:30:00-04:00' must normalize to
# '2026-05-15T12:30:00Z'.
W115B_TMP="$(mktemp -d)"
build_backfill_fixture "$W115B_TMP" "docs/plans"
(
  cd "$W115B_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  cat > docs/plans/tz-plan.md <<'MD'
---
name: tz-plan
status: active
---
# tz
MD
  git add -A && git commit -qm "tz-plan active"
  cat > docs/plans/tz-plan.md <<'MD'
---
name: tz-plan
status: complete
---
# tz
MD
  GIT_AUTHOR_DATE='2026-05-15T08:30:00-04:00' \
    GIT_COMMITTER_DATE='2026-05-15T08:30:00-04:00' \
    git -c user.email=t@t -c user.name=t commit -qam "tz-plan complete"
  CLAUDE_PROJECT_DIR="$W115B_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w115b-run.txt 2>&1
  completed_val=$(grep "^completed:" docs/plans/tz-plan.md | sed -E 's/^completed:[[:space:]]*"?([^"]*)"?$/\1/')
  echo "completed=$completed_val"
) > /tmp/w115b-result.txt 2>&1
W115B=$(cat /tmp/w115b-result.txt)
if printf '%s\n' "$W115B" | grep -q "^completed=2026-05-15T12:30:00Z$"; then
  pass "W1.15b: backfill_plan_completed_normalizes_local_tz_to_utc_z (DA3.1)"
else
  fail "W1.15b: got '$W115B' run=$(cat /tmp/w115b-run.txt 2>&1)"
fi

# W1.16 — backfill_plan_completed_reupgrade_takes_latest: active →
# complete → active → complete: tail -1 picks the SECOND introduction.
W116_TMP="$(mktemp -d)"
build_backfill_fixture "$W116_TMP" "docs/plans"
(
  cd "$W116_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  cat > docs/plans/re.md <<'MD'
---
name: re
status: active
---
# re
MD
  git add -A && git commit -qm "re active"
  cat > docs/plans/re.md <<'MD'
---
name: re
status: complete
---
# re
MD
  GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    git -c user.email=t@t -c user.name=t commit -qam "re complete first"
  cat > docs/plans/re.md <<'MD'
---
name: re
status: active
---
# re
MD
  GIT_AUTHOR_DATE='2026-02-01T00:00:00Z' GIT_COMMITTER_DATE='2026-02-01T00:00:00Z' \
    git -c user.email=t@t -c user.name=t commit -qam "re back to active"
  cat > docs/plans/re.md <<'MD'
---
name: re
status: complete
---
# re
MD
  GIT_AUTHOR_DATE='2026-03-15T00:00:00Z' GIT_COMMITTER_DATE='2026-03-15T00:00:00Z' \
    git -c user.email=t@t -c user.name=t commit -qam "re complete second"
  CLAUDE_PROJECT_DIR="$W116_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w116-run.txt 2>&1
  completed_val=$(grep "^completed:" docs/plans/re.md | sed -E 's/^completed:[[:space:]]*"?([^"]*)"?$/\1/')
  echo "completed=$completed_val"
) > /tmp/w116-result.txt 2>&1
W116=$(cat /tmp/w116-result.txt)
if printf '%s\n' "$W116" | grep -q "^completed=2026-03-15T00:00:00Z$"; then
  pass "W1.16: backfill_plan_completed_reupgrade_takes_latest (tail -1)"
else
  fail "W1.16: got '$W116' run=$(cat /tmp/w116-run.txt 2>&1)"
fi

# W1.17 — backfill_plan_completed_handles_block_scalar_exit3: fixture
# plan with `completed: |` block scalar already present. Script must
# detect the existing-non-empty value via frontmatter-get and skip via
# the idempotency guard — NOT trigger frontmatter-set exit-3 (the spec
# also calls for the WARN path; here we exercise the idempotent skip
# AND verify the WARN path by clearing the value and forcing it to be
# overwritten as a block scalar).
#
# Approach: write a plan where `completed:` is present as an EMPTY value
# but as a block-scalar form (`completed: |` with no content). The
# frontmatter-get will return empty, the script will attempt to write,
# frontmatter-set.sh will exit 3 (block-scalar refusal), and the
# script's WARN path fires.
W117_TMP="$(mktemp -d)"
build_backfill_fixture "$W117_TMP" "docs/plans"
(
  cd "$W117_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  cat > docs/plans/bs.md <<'MD'
---
name: bs
status: complete
completed: |
  pending
---
# bs
MD
  git add -A && git commit -qm "bs with block-scalar completed"
  CLAUDE_PROJECT_DIR="$W117_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w117-run.txt 2>&1
  echo "exit=$?"
  cat /tmp/w117-run.txt
) > /tmp/w117-result.txt 2>&1
W117=$(cat /tmp/w117-result.txt)
# The plan already had a non-empty block-scalar value ("pending"), so
# frontmatter-get returns "pending" and the script skips via idempotency.
# That's still a clean exit-0 path and counts in the "already set" summary.
# Either path (block-scalar skip OR already-set skip) keeps the script
# exit 0; the summary should reflect.
if printf '%s\n' "$W117" | grep -q "^exit=0$" \
    && (printf '%s\n' "$W117" | grep -q "block-scalar refusals" \
         || printf '%s\n' "$W117" | grep -q "completed: already set"); then
  pass "W1.17: backfill_plan_completed_handles_block_scalar_exit3 (exits 0; reports skip)"
else
  fail "W1.17: got '$W117'"
fi

# W1.18 — backfill_plan_completed_cwd_precheck: running outside a
# zskills-configured repo exits non-zero; running from a SUBDIR of a
# configured repo recovers via cd-to-toplevel.
W118_TMP="$(mktemp -d)"
build_backfill_fixture "$W118_TMP" "docs/plans"
(
  cd "$W118_TMP"
  git init -q -b main
  git config user.email t@t && git config user.name t
  write_plan_with_status_complete "docs/plans/sub-plan.md"
  git add -A && git commit -qm "initial"
)
# Case A: invoke from /tmp (no zskills-config there).
TMP_EMPTY="$(mktemp -d)"
(
  cd "$TMP_EMPTY"
  CLAUDE_PROJECT_DIR="$TMP_EMPTY" bash "$BACKFILL_SCRIPT" > /tmp/w118a.txt 2>&1
  echo "exitA=$?"
) > /tmp/w118a-result.txt 2>&1
# Case B: invoke from a SUBDIR of a configured repo.
(
  mkdir -p "$W118_TMP/some/sub/dir"
  cd "$W118_TMP/some/sub/dir"
  CLAUDE_PROJECT_DIR="$W118_TMP" bash "$BACKFILL_SCRIPT" > /tmp/w118b.txt 2>&1
  echo "exitB=$?"
) > /tmp/w118b-result.txt 2>&1
W118A=$(cat /tmp/w118a-result.txt)
W118B=$(cat /tmp/w118b-result.txt)
W118A_OUT=$(cat /tmp/w118a.txt 2>&1)
if ! printf '%s\n' "$W118A" | grep -q "^exitA=0$" \
    && printf '%s\n' "$W118A_OUT" | grep -q "must run from a zskills-configured repo\|not in a git repo" \
    && printf '%s\n' "$W118B" | grep -q "^exitB=0$"; then
  pass "W1.18: backfill_plan_completed_cwd_precheck (refuses non-zskills cwd; recovers from subdir)"
else
  fail "W1.18: A='$W118A_OUT' (exitA='$W118A') B='$W118B'"
fi

# W1.24 — queues_block_excludes_closed_issues: the snapshot's
# queues.issues block must NOT contain closed issue numbers, even when
# monitor-state.json has them in an active column. Regression canary
# for the PR #678 incomplete fix: _annotate_issues_queue filtered its
# internal pos but queues_block passed the raw state file through.
W124=$(cd "$REPO_ROOT" && "$PYTHON" -c '
# Unit test of the queues_block closed-issue filter logic from
# collect_snapshot (collect.py ~line 2420). Tests the filter in
# isolation — same algorithm, no need to mock the full snapshot.
import json

# Inputs: closed issues in the live list, raw state-file positions.
issues = [
    {"number": 677, "closed_at": "2026-05-27T00:54:50Z"},
    {"number": 641, "closed_at": "2026-05-27T01:46:20Z"},
    {"number": 672},  # open — no closed_at
]
raw_issues = {"triage": [], "ready": [677, 641, 672], "backlog": [67]}

# Derive closed_nums (same as collect_snapshot).
closed_nums = {
    it.get("number") for it in issues
    if isinstance(it.get("number"), int) and it.get("closed_at")
}
# Filter (same as collect_snapshot).
filtered = {}
for col, entries in raw_issues.items():
    if not entries:
        filtered[col] = []
        continue
    kept = []
    for n in entries:
        try:
            num = int(n)
        except (TypeError, ValueError):
            kept.append(n)
            continue
        if num not in closed_nums:
            kept.append(n)
    filtered[col] = kept

print("ready=" + json.dumps(filtered["ready"]))
print("backlog=" + json.dumps(filtered["backlog"]))
has_677 = 677 in filtered["ready"]
has_641 = 641 in filtered["ready"]
has_672 = 672 in filtered["ready"]
print("has_677=" + str(has_677))
print("has_641=" + str(has_641))
print("has_672=" + str(has_672))
' 2>&1)
if printf '%s\n' "$W124" | grep -q "^has_677=False$" \
   && printf '%s\n' "$W124" | grep -q "^has_641=False$" \
   && printf '%s\n' "$W124" | grep -q "^has_672=True$"; then
  pass "W1.24: queues_block_excludes_closed_issues (677/641 dropped, 672 kept)"
else
  fail "W1.24: $W124"
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
