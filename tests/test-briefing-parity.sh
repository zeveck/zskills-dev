#!/bin/bash
# Tests for skills/briefing/scripts/briefing.py
# Run from repo root: bash tests/test-briefing-parity.sh
#
# Historical note: this file previously asserted runtime parity between
# briefing.cjs and briefing.py. The cjs fork was retired in #289 (Python
# became the single runtime; see CLAUDE.md "Python is required"). The
# filename is retained for git-history continuity; the contents are now
# pure smoke tests against briefing.py.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

skip() {
  printf '\033[33m  SKIP\033[0m %s\n' "$1"
  ((SKIP_COUNT++))
}

HAS_PYTHON=false
command -v python3 >/dev/null 2>&1 && HAS_PYTHON=true

echo "=== briefing.py smoke tests ==="

if [[ "$HAS_PYTHON" == "false" ]]; then
  echo "python3 not available — skipping all tests"
  skip "python3 not available"
  echo ""
  echo "---"
  printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
  exit 0
fi

# Use a temp directory for report output to avoid polluting the repo
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Smoke test all subcommands with python3. Each subcommand asserts a
# stable expected substring in its actual output — NOT "exit 0 + any
# output" (issue #517: that latter form is tautological because every
# non-zero-exit and every empty-stdout-but-stderr-warning case passes,
# masking real "subcommand handler returned empty string" regressions).
# Note: "report" writes files, so its stdout includes the "Report
# written to: <path>" confirmation line + the file body.
#
# Per-subcommand expected substring (rationale):
#   summary     — top-of-output banner is always "BRIEFING — <date>"
#   report      — emits "Report written to:" then markdown header begins
#                 with "# Briefing Report —"; check for the file header
#                 in the OUTPUT FILE rather than stdout (stdout is the
#                 single confirmation line).
#   verify      — emits one of "VERIFICATION NEEDED" / "NO VERIFICATION
#                 NEEDED" depending on plan-report state. Match either.
#   current     — top header is "CURRENTLY IN FLIGHT —"
#   worktrees   — emits a JSON array; the first object always has
#                 `"path":` (every worktree has a path). Match `"path":`.
#   commits     — emits a JSON array; every commit object has `"hash":`.
#   checkboxes  — emits a JSON array; objects have `"file":` keys. Empty
#                 array `[]` is also valid (no plan reports = no checkboxes),
#                 so accept either `"file":` OR a literal `[]` whole-output.
smoke_cmds=(
  "summary|BRIEFING —"
  "report --since=24h --output=$TEST_TMPDIR/briefing-test.md|Report written to:"
  "verify|VERIFICATION"
  "current|CURRENTLY IN FLIGHT"
  "worktrees|\"path\":"
  "commits --since=24h|\"hash\":"
  "checkboxes|"  # custom-matched below (allow empty-array)
)

for entry in "${smoke_cmds[@]}"; do
  cmd="${entry%%|*}"
  expected="${entry#*|}"
  # shellcheck disable=SC2086
  output=$(cd "$REPO_ROOT" && python3 "$REPO_ROOT/skills/briefing/scripts/briefing.py" $cmd 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    fail "python3 briefing.py $cmd (exit=$exit_code)"
    continue
  fi

  if [[ "$cmd" == "checkboxes" ]]; then
    # checkboxes: accept either non-empty JSON-array-with-"file": OR a
    # literal empty array "[]" (legitimate when no plan reports exist).
    trimmed=$(printf '%s' "$output" | tr -d '[:space:]')
    if [[ "$trimmed" == "[]" ]] || printf '%s' "$output" | grep -q '"file":'; then
      pass "python3 briefing.py $cmd (JSON array)"
    else
      fail "python3 briefing.py $cmd (expected '\"file\":' key or '[]'; got: $output)"
    fi
    continue
  fi

  if [[ "$cmd" == report* ]]; then
    # report: stdout has "Report written to:"; ALSO verify the written
    # file contains the "# Briefing Report —" header (catches a regression
    # where the handler prints the confirmation but emits an empty file).
    if printf '%s' "$output" | grep -qF "$expected" \
       && grep -qF '# Briefing Report —' "$TEST_TMPDIR/briefing-test.md"; then
      pass "python3 briefing.py $cmd"
    else
      fail "python3 briefing.py $cmd (stdout missing '$expected' or output file missing '# Briefing Report —' header)"
    fi
    continue
  fi

  if printf '%s' "$output" | grep -qF "$expected"; then
    pass "python3 briefing.py $cmd"
  else
    fail "python3 briefing.py $cmd (expected '$expected' in output; got first 200 chars: $(printf '%s' "$output" | head -c 200))"
  fi
done

# ---------------------------------------------------------------------
# Port-failure regression guard (restored from pre-#312 test history;
# see issue #338). Original section was trimmed in 1690c93 alongside the
# cjs retirement, but the Python invariant remains worth asserting.
#
# Invariant: when port.sh is NOT installed at
# .claude/skills/update-zskills/scripts/port.sh, briefing.py must
# (a) exit 0 and (b) emit zero `localhost:` URLs. The pre-Phase-4
# fallback (`port = '8080'`) would emit `localhost:8080/...`
# unconditionally; this guards against that regression returning.
# ---------------------------------------------------------------------
echo ""
echo "=== Port-failure regression guard (no port.sh installed) ==="

FIXTURE_DIR="/tmp/zskills-briefing-fixture-noport-$$"
rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR/skills/briefing/scripts"
# .git marker so find_repo_root anchors at FIXTURE_DIR (and therefore
# the absent .claude/skills/update-zskills/scripts/port.sh is what gets
# resolved — NOT the real one from the surrounding repo).
mkdir -p "$FIXTURE_DIR/.git"
# Copy briefing.py into the fixture so __file__ / _SCRIPT_DIR resolve
# to fixture paths. (find_repo_root walks up from the script's
# directory, not cwd.) NO port.sh is installed in the fixture's
# .claude/skills/update-zskills/scripts/ tree — that absence is the
# whole point of the test.
cp "$REPO_ROOT/skills/briefing/scripts/briefing.py" \
   "$FIXTURE_DIR/skills/briefing/scripts/briefing.py"

# Ensure cleanup even on early exit / failures below.
trap 'rm -rf "$TEST_TMPDIR" "$FIXTURE_DIR"' EXIT

noport_py_out="$FIXTURE_DIR/.py-summary.txt"
py_exit=0
(cd "$FIXTURE_DIR" && python3 \
  "$FIXTURE_DIR/skills/briefing/scripts/briefing.py" summary --since=24h) \
  >"$noport_py_out" 2>"$FIXTURE_DIR/.py-err.txt" || py_exit=$?

# AC 1: briefing.py exits 0 with missing port.sh.
if [[ "$py_exit" -eq 0 ]]; then
  pass "port-failure: briefing.py exits 0 on missing port.sh"
else
  fail "port-failure: briefing.py exit=$py_exit on missing port.sh"
fi

# AC 2: no localhost: URL in stdout.
# `grep -c` returns exit 1 when there are zero matches; the count is
# still printed (as "0"), but we tolerate the empty-output case too.
py_localhost=$(grep -c 'localhost:' "$noport_py_out" 2>/dev/null)
[[ -z "$py_localhost" ]] && py_localhost=0
if [[ "$py_localhost" -eq 0 ]]; then
  pass "port-failure: briefing.py emits no localhost: URL"
else
  fail "port-failure: briefing.py emitted $py_localhost localhost: URL(s)"
fi

# ---------------------------------------------------------------------
# PR-squash-merge subject-match regression guard (issue #474).
#
# GitHub squash-merge appends ` (#NNN)` to the subject on main. The
# worktree's pre-merge subject has no such suffix. partition_commits_by_
# landing previously did literal string equality, so every PR-mode landed
# worktree was misclassified as unlanded ("NOT SAFE"). The fix strips the
# trailing `\s*\(#\d+\)\s*$` from the main-side subjects before
# comparison. This guard exercises BOTH directions:
#   (a) main subject with `(#123)` suffix → matches plain worktree subject
#   (b) main subject without suffix (legacy direct-commit) → still matches
#   (c) middle-of-subject `(#NNN)` parenthetical → NOT stripped (anchor $)
# ---------------------------------------------------------------------
echo ""
echo "=== PR-squash-merge subject-match (issue #474) ==="

pr_suffix_out="$TEST_TMPDIR/pr-suffix.txt"
pr_suffix_exit=0
python3 - "$REPO_ROOT" >"$pr_suffix_out" 2>&1 <<'PYEOF' || pr_suffix_exit=$?
import sys, os
repo_root = sys.argv[1]
sys.path.insert(0, os.path.join(repo_root, 'skills', 'briefing', 'scripts'))
import briefing  # noqa: E402

# Case (a): squash-merged subject on main matches plain worktree subject.
wt = [
    {'subject': 'feat: foo', 'hash': 'abc1', 'date': ''},
    {'subject': 'feat: bar', 'hash': 'abc2', 'date': ''},
]
main = {'feat: foo (#123)', 'feat: bar (#124)'}
res = briefing.partition_commits_by_landing(wt, main)
assert len(res['landed']) == 2, f"(a) expected 2 landed, got {res}"
assert len(res['unlanded']) == 0, f"(a) expected 0 unlanded, got {res}"

# Case (b): legacy direct-commit (no suffix on main) still matches.
wt = [{'subject': 'docs: tweak', 'hash': 'def1', 'date': ''}]
main = {'docs: tweak'}
res = briefing.partition_commits_by_landing(wt, main)
assert len(res['landed']) == 1, f"(b) expected 1 landed, got {res}"

# Case (c): genuinely unlanded commit stays unlanded.
wt = [{'subject': 'feat: not yet shipped', 'hash': 'ghi1', 'date': ''}]
main = {'feat: something else (#99)'}
res = briefing.partition_commits_by_landing(wt, main)
assert len(res['unlanded']) == 1, f"(c) expected 1 unlanded, got {res}"
assert len(res['landed']) == 0, f"(c) expected 0 landed, got {res}"

# Case (d): middle-of-subject `(#NNN)` parenthetical reference is NOT
# stripped — anchor `$` only matches end-of-subject. Worktree subject
# carrying mid-string `(#42)` should still match its main-side twin.
wt = [{'subject': 'fix: address (#42) regression', 'hash': 'jkl1', 'date': ''}]
main = {'fix: address (#42) regression (#777)'}
res = briefing.partition_commits_by_landing(wt, main)
assert len(res['landed']) == 1, f"(d) expected 1 landed, got {res}"

# Case (e): if a worktree subject differs from main's stripped form, it's unlanded.
wt = [{'subject': 'feat: unrelated', 'hash': 'mno1', 'date': ''}]
main = {'feat: something (#1)'}
res = briefing.partition_commits_by_landing(wt, main)
assert len(res['unlanded']) == 1, f"(e) expected 1 unlanded, got {res}"

print("OK")
PYEOF

if [[ "$pr_suffix_exit" -eq 0 ]] && grep -q '^OK$' "$pr_suffix_out"; then
  pass "issue #474: partition_commits_by_landing strips PR-squash-merge (#NNN) suffix"
else
  fail "issue #474: partition_commits_by_landing regression"
  echo "--- output ---"
  cat "$pr_suffix_out"
  echo "--------------"
fi

# ---------------------------------------------------------------------
# Main-subjects cap removal (issue #475).
#
# `worktrees_status` used to call `git log main --format="%s" -n 500`,
# which silently truncated `main_subjects` on any repo whose main had
# grown past 500 commits — misclassifying older landed worktrees as
# "NOT SAFE — unlanded commits". The fix drops the `-n 500` flag.
#
# Two checks:
#   (a) the `-n 500` substring no longer appears in that call site
#       (source-level regression guard).
#   (b) partition_commits_by_landing matches a worktree subject whose
#       main-side twin sits at position 600 in a >500-entry set — the
#       case the cap previously broke.
# ---------------------------------------------------------------------
echo ""
echo "=== Main-subjects cap removal (issue #475) ==="

# (a) Source-level: the cap is gone from the call site.
if grep -q 'git log main --format="%s" -n 500' "$REPO_ROOT/skills/briefing/scripts/briefing.py"; then
  fail "issue #475: -n 500 cap still present in briefing.py git log main call"
else
  pass "issue #475: -n 500 cap removed from briefing.py git log main call"
fi

# (b) Behavioral: 600-subject main set still matches older subjects.
cap_out="$TEST_TMPDIR/cap-removal.txt"
cap_exit=0
python3 - "$REPO_ROOT" >"$cap_out" 2>&1 <<'PYEOF' || cap_exit=$?
import sys, os
repo_root = sys.argv[1]
sys.path.insert(0, os.path.join(repo_root, 'skills', 'briefing', 'scripts'))
import briefing  # noqa: E402

# Simulate a 600-commit main where the worktree's subject is older than
# position 500 — the case the -n 500 cap previously truncated away.
main_subjects = {f'feat: commit {i:04d} (#{i})' for i in range(600)}
# Older landed subject — would have been outside the most-recent 500.
wt = [{'subject': 'feat: commit 0050', 'hash': 'old1', 'date': ''}]
res = briefing.partition_commits_by_landing(wt, main_subjects)
assert len(res['landed']) == 1, f"expected 1 landed, got {res}"
assert len(res['unlanded']) == 0, f"expected 0 unlanded, got {res}"

print("OK")
PYEOF

if [[ "$cap_exit" -eq 0 ]] && grep -q '^OK$' "$cap_out"; then
  pass "issue #475: partition matches older subjects in >500-entry main set"
else
  fail "issue #475: cap-removal behavioral check"
  echo "--- output ---"
  cat "$cap_out"
  echo "--------------"
fi

# ---------------------------------------------------------------------
# Live PR-state upgrade for stale .landed markers (issue #476).
#
# briefing.py:335-361 used to derive `landed-pr-ready` /
# `landed-pr-needs-attention` purely from the `.landed` marker, which is
# written once at landing time and never reflects subsequent GitHub
# lifecycle. The fix calls `gh pr view --json state,mergeStateStatus`
# and upgrades MERGED → `landed-pr-merged`, CLOSED-unmerged →
# `landed-pr-abandoned`, OPEN → keep marker-derived category.
#
# This test stubs the helper directly (no real gh call) by injecting
# entries into the in-process `_PR_STATE_CACHE` before re-running
# classification on a synthetic .landed file.
# ---------------------------------------------------------------------
echo ""
echo "=== Live PR-state upgrade (issue #476) ==="

issue476_out="$TEST_TMPDIR/issue-476.txt"
issue476_exit=0
python3 - "$REPO_ROOT" >"$issue476_out" 2>&1 <<'PYEOF' || issue476_exit=$?
import sys, os
repo_root = sys.argv[1]
sys.path.insert(0, os.path.join(repo_root, 'skills', 'briefing', 'scripts'))
import briefing  # noqa: E402

# (a) parse_landed extracts the `pr:` URL.
content = '\n'.join([
    'status: pr-ready',
    'date: 2026-05-20T00:00:00-05:00',
    'source: land-pr',
    'method: pr',
    'branch: fix/test-476',
    'pr: https://github.com/owner/repo/pull/12345',
    'commits: abc1 def2',
])
landed = briefing.parse_landed(content)
assert landed.get('status') == 'pr-ready', f"(a-status) got {landed}"
assert landed.get('pr') == 'https://github.com/owner/repo/pull/12345', f"(a-pr) got {landed}"
assert landed.get('branch') == 'fix/test-476', f"(a-branch) got {landed}"

# (b) _pr_number_from extracts numeric PR from various URL shapes.
assert briefing._pr_number_from('https://github.com/o/r/pull/42') == '42'
assert briefing._pr_number_from('#7') == '7'
assert briefing._pr_number_from('123') == '123'
assert briefing._pr_number_from(None, branch='feat/foo') == 'branch:feat/foo'
assert briefing._pr_number_from(None) is None

# (c) query_pr_state honors the in-process cache (avoids gh roundtrips
# within a single briefing run).
briefing._PR_STATE_CACHE.clear()
briefing._PR_STATE_CACHE['9999'] = {'state': 'MERGED', 'mergeStateStatus': 'CLEAN'}
got = briefing.query_pr_state('https://github.com/o/r/pull/9999')
assert got == {'state': 'MERGED', 'mergeStateStatus': 'CLEAN'}, f"(c) got {got}"

# (d) Category mapping: pre-seed cache for branch keys and re-run the
# branch in classify_worktrees' status->category logic verbatim. We
# can't easily run full classify_worktrees without a git tree, so
# replicate the decision block from briefing.py:335-361.
def categorize(marker_status, live):
    if marker_status in ('pr-ready',):
        base = 'landed-pr-ready'
    elif marker_status in ('pr-ci-failing', 'pr-failed', 'conflict', 'pr-state-unknown'):
        base = 'landed-pr-needs-attention'
    else:
        return None
    if live is None:
        return base
    s = live.get('state')
    if s == 'MERGED':
        return 'landed-pr-merged'
    if s == 'CLOSED':
        return 'landed-pr-abandoned'
    return base

# MERGED upgrades a pr-ready marker.
assert categorize('pr-ready', {'state': 'MERGED', 'mergeStateStatus': None}) == 'landed-pr-merged'
# MERGED upgrades a pr-ci-failing marker too (CI failed, agent fixed it, merged).
assert categorize('pr-ci-failing', {'state': 'MERGED', 'mergeStateStatus': None}) == 'landed-pr-merged'
# CLOSED (without merge) downgrades to abandoned.
assert categorize('pr-ready', {'state': 'CLOSED', 'mergeStateStatus': None}) == 'landed-pr-abandoned'
# OPEN keeps the marker-derived category.
assert categorize('pr-ready', {'state': 'OPEN', 'mergeStateStatus': 'BLOCKED'}) == 'landed-pr-ready'
assert categorize('pr-ci-failing', {'state': 'OPEN', 'mergeStateStatus': 'BLOCKED'}) == 'landed-pr-needs-attention'
# gh failure (live == None) falls back to marker-derived category — briefing
# stays functional offline.
assert categorize('pr-ready', None) == 'landed-pr-ready'
assert categorize('pr-state-unknown', None) == 'landed-pr-needs-attention'

# (e) query_pr_state degrades gracefully when gh is missing / fails.
# Override PATH so `gh` isn't found, clear cache, and assert None.
briefing._PR_STATE_CACHE.clear()
orig_path = os.environ.get('PATH', '')
os.environ['PATH'] = '/nonexistent'
try:
    got = briefing.query_pr_state('https://github.com/o/r/pull/77777')
    assert got is None, f"(e) expected None on gh-missing, got {got}"
    # And the failure was cached (no retry within the run).
    assert briefing._PR_STATE_CACHE.get('77777') is None
    assert '77777' in briefing._PR_STATE_CACHE
finally:
    os.environ['PATH'] = orig_path

print("OK")
PYEOF

if [[ "$issue476_exit" -eq 0 ]] && grep -q '^OK$' "$issue476_out"; then
  pass "issue #476: live PR-state upgrades stale .landed category"
else
  fail "issue #476: live PR-state upgrade"
  echo "--- output ---"
  cat "$issue476_out"
  echo "--------------"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
