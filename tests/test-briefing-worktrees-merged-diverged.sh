#!/bin/bash
# Issue #516 regression: briefing.py worktrees-status must NOT classify a
# worktree as safe_to_remove when the PR is MERGED but the local branch
# has commits not on main. `gh pr view` is sticky after merge — once
# MERGED it never reverts to OPEN, so checking gh state alone leaves a
# silent-commit-loss hole.
#
# Strategy: stub the `gh` binary on PATH with a script that always
# reports state=MERGED. Set up a tmp repo + worktree where the branch
# has a commit not present on main. Invoke briefing.py worktrees-status
# --json and assert:
#   1. the worktree does NOT appear in `safe_to_remove`
#   2. its category is `landed-pr-merged-but-diverged`
#   3. the rendered (non-JSON) output contains a NOT SAFE / investigate hint
#
# Run from repo root: bash tests/test-briefing-worktrees-merged-diverged.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIEFING="$REPO_ROOT/skills/briefing/scripts/briefing.py"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

echo "=== briefing worktrees-status — PR=MERGED + ahead>0 gate (issue #516) ==="

if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not available"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
  exit 0
fi

WORK="/tmp/zskills-tests/$(basename "$REPO_ROOT")/briefing-merged-diverged-$$"
rm -rf "$WORK"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Stub gh — always reports state=MERGED for `gh pr view ... --json state`.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
# Match: gh pr view <ref> --json state -q .state
# Print MERGED for any pr view invocation; tolerate other subcommands by exit 0.
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  # If `--json state -q .state` style query, print just MERGED. Otherwise JSON.
  for a in "$@"; do
    if [ "$a" = ".state" ]; then echo "MERGED"; exit 0; fi
  done
  echo '{"state":"MERGED","number":9999}'
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/gh"

# Set up tmp git repo + worktree.
MAIN="$WORK/main"
mkdir -p "$MAIN"
(
  cd "$MAIN" &&
  git init -q -b main &&
  git config user.email "test@example.com" &&
  git config user.name  "Test" &&
  echo init > a.txt &&
  git add a.txt &&
  git commit -q -m "init"
)

# Make a worktree on a feature branch with one commit NOT on main.
# Use `agent-` prefix so classify_worktrees doesn't fast-path it to
# category=named (named long-running worktrees skip PR-state checks).
WT="$WORK/agent-feat-diverged"
(
  cd "$MAIN" &&
  git worktree add -q -b feat/diverged "$WT"
)
(
  cd "$WT" &&
  echo post-merge > b.txt &&
  git add b.txt &&
  git commit -q -m "post-merge commit (simulates divergence after PR merge)"
)

# Write a .landed marker indicating a PR was opened+merged.
cat > "$WT/.landed" <<LANDED
status: pr-ready
pr: 9999
date: 2026-05-21T00:00:00-04:00
LANDED

# Invoke briefing.py worktrees-status against this tmp main repo, with
# our gh stub on PATH.
export PATH="$WORK/bin:$PATH"
export CLAUDE_PROJECT_DIR="$MAIN"

# Import classify_worktrees directly to inspect category assignment; no
# JSON CLI exists for worktrees-status, so we drive the function.
JSON_OUT=$(cd "$MAIN" && python3 -c "
import sys, json, os
sys.path.insert(0, os.path.dirname('$BRIEFING'))
import briefing
wts = briefing.classify_worktrees(repo_root='$MAIN')
print(json.dumps({'worktrees': wts}, default=str))
" 2>"$WORK/stderr") || true
TEXT_OUT=$(cd "$MAIN" && python3 -c "
import sys, os
sys.path.insert(0, os.path.dirname('$BRIEFING'))
import briefing
wts = briefing.classify_worktrees(repo_root='$MAIN')
print(briefing.format_worktrees_status(wts, opts={'repoRoot': '$MAIN'}))
" 2>>"$WORK/stderr") || true

# Sanity: gh stub reachable
if ! command -v gh >/dev/null 2>&1; then
  fail "gh stub not on PATH (test setup error)"
fi
STUB_CHECK=$(gh pr view feat/diverged --json state -q .state 2>/dev/null || echo "")
if [ "$STUB_CHECK" = "MERGED" ]; then
  pass "gh stub reports MERGED"
else
  fail "gh stub did not return MERGED (got: $STUB_CHECK)"
fi

# Assertion 1: JSON output's worktrees list contains an entry for our
# worktree, and its category is landed-pr-merged-but-diverged (NOT
# landed-pr-merged).
if echo "$JSON_OUT" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
wts = data.get('worktrees', [])
hit = [w for w in wts if w.get('branch') == 'feat/diverged']
if not hit:
    print('NO_WT', json.dumps(wts))
    sys.exit(2)
wt = hit[0]
cat = wt.get('category', '')
ahead = wt.get('ahead', 0)
if cat == 'landed-pr-merged-but-diverged' and ahead >= 1:
    sys.exit(0)
print('WRONG_CAT', cat, 'ahead=', ahead)
sys.exit(3)
" 2>"$WORK/py-err"; then
  pass "category = landed-pr-merged-but-diverged when PR=MERGED + ahead>0"
else
  fail "category wrong — expected landed-pr-merged-but-diverged ($(cat "$WORK/py-err" 2>/dev/null))"
  echo "--- JSON dump (first 80 lines) ---" >&2
  echo "$JSON_OUT" | head -80 >&2
fi

# Assertion 2: the worktree does NOT appear in safe_to_remove. Use the
# rendered text output (safe_to_remove is a textual section).
if echo "$TEXT_OUT" | awk '
  /^SAFE TO REMOVE/ {in_section=1; next}
  /^[A-Z]/ && in_section {in_section=0}
  in_section {print}
' | grep -q 'feat/diverged\|agent-feat-diverged'; then
  fail "worktree wrongly appears under SAFE TO REMOVE"
  echo "$TEXT_OUT" >&2
else
  pass "worktree absent from SAFE TO REMOVE section"
fi

# Assertion 3: a NOT SAFE / investigate hint surfaces the worktree.
if echo "$TEXT_OUT" | grep -qE 'NOT SAFE.*unlanded|investigate.*#?516|commits not on main'; then
  pass "worktree surfaced via NOT SAFE / investigate hint"
else
  fail "no NOT SAFE / investigate hint in text output"
  echo "$TEXT_OUT" >&2
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
