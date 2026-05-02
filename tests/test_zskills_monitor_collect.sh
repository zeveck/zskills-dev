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

EXPECTED_KEYS="activity branches errors issues plans queues repo_root state_file_path updated_at version worktrees"
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
issues = c.list_issues(errs, _now=1.0, _runner=boom)
print(len(issues), len(errs), errs[0]["source"] if errs else "")
')
if [ "$GH_MISSING" = "0 1 gh issue list" ]; then
  pass "missing gh: issues=[] + 'gh issue list' error, no exception"
else
  fail "missing gh: got '$GH_MISSING'"
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
