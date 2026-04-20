#!/bin/bash
# Tests that skill files preserve critical behavior-contract patterns
# that downstream tooling greps for. Designed as a safety net for the
# RESTRUCTURE plan: when /run-plan/SKILL.md (and siblings) split into
# modes/*.md and references/*.md, critical invariants must still exist
# SOMEWHERE in the skill's directory tree.
#
# Each `check` greps the entire skills/<skill>/ tree (recursive), so
# patterns succeed whether they live in SKILL.md, modes/X.md, or
# references/X.md. If RESTRUCTURE drops a critical pattern, this test
# fails and CI halts.
#
# Patterns target: behavior contracts, structural landmarks, named
# variables with cross-boundary meaning, and shell idioms critical to
# correctness. Prose and cosmetic phrasing are NOT checked — those can
# drift freely during extraction.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Env-overridable so drift-detection tests (and any future scaffolding)
# can point the checks at a non-default tree.
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — pattern not found: %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# check <skill> <label> <pattern>
# Greps skills/<skill>/ recursively. Pattern is extended regex.
# Uses `-e` to ensure patterns starting with `-` (e.g. `--watch`) aren't
# treated as flags.
check() {
  local skill="$1" label="$2" pattern="$3"
  if grep -rE -e "$pattern" "$REPO_ROOT/skills/$skill/" > /dev/null 2>&1; then
    pass "[$skill] $label"
  else
    fail "[$skill] $label" "$pattern"
  fi
}

# check_fixed <skill> <label> <literal>
# Like `check` but uses fixed-string (-F) matching for literals with regex metachars.
check_fixed() {
  local skill="$1" label="$2" pattern="$3"
  if grep -rF -e "$pattern" "$REPO_ROOT/skills/$skill/" > /dev/null 2>&1; then
    pass "[$skill] $label"
  else
    fail "[$skill] $label" "$pattern"
  fi
}

echo "=== /run-plan — behavior contracts ==="
check       run-plan "stop-precedence"              'Takes precedence'
check_fixed run-plan "landing-default"              'LANDING_MODE="cherry-pick"'
check       run-plan "direct+main_protected guard"  'direct mode is incompatible with main_protected'
check_fixed run-plan "cherry-pick create-worktree"  '--prefix cp'
check_fixed run-plan "cp worktree slug suffix"      '"${PLAN_SLUG}-phase-${PHASE}"'
check_fixed run-plan "pr worktree path"             'WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-'
check_fixed run-plan "pipeline-id echo"             'ZSKILLS_PIPELINE_ID=run-plan.'
check_fixed run-plan ".zskills-tracked write"       '.zskills-tracked'
check_fixed run-plan "test-out per-worktree"        'TEST_OUT="/tmp/zskills-tests/'
check_fixed run-plan "test capture redirect"        '.test-results.txt" 2>&1'
check_fixed run-plan "compute-cron-fire invocation" 'bash scripts/compute-cron-fire.sh'
check       run-plan "cron tz warning"              'date.*SYSTEM-local|system-local'
check       run-plan "--watch unreliable"           '--watch.*(exit code is unreliable|UNRELIABLE)'
check_fixed run-plan "gh pr checks re-check"        'gh pr checks "$PR_NUMBER"'
check_fixed run-plan "timeout 124 handling"         'WATCH_EXIT" -eq 124'
check_fixed run-plan "ci-pending pr-ready"          'pr-ready'
check_fixed run-plan "ci log path"                  '/tmp/ci-failure-'
check       run-plan "auto-merge expected fallback"  'auto-merge enabled|expected.{0,15}auto-merge'
check_fixed run-plan "pr number from url"           'PR_NUMBER="${PR_URL##*/}"'
check       run-plan "pr number numeric check"      'PR_NUMBER" =~ \^\[0-9\]\+\$'
check       run-plan "push error-check first-time"  'if ! git push -u origin'
check       run-plan "pre-cherry-pick stash"        'pre-cherry-pick stash'
check_fixed run-plan "write-landed invocation"      'bash scripts/write-landed.sh'
check_fixed run-plan "pr-mode bookkeeping"          'PR-mode bookkeeping'
check_fixed run-plan "post-run-invariants"          'bash scripts/post-run-invariants.sh'
check_fixed run-plan "final-verify marker glob"     'requires.verify-changes.final.'

echo ""
echo "=== /run-plan — structural landmarks ==="
check run-plan "Phase 5b header"    '^## Phase 5b'
check run-plan "Phase 5c header"    '^## Phase 5c'
check run-plan "Phase 6 header"     '^## Phase 6'
check run-plan "Failure Protocol"   '^## Failure Protocol'

echo ""
echo "=== /run-plan — shell idioms ==="
check_fixed run-plan "worktree-add-safe"     'bash scripts/worktree-add-safe.sh'
check_fixed run-plan "allow-branch-resume"   'ZSKILLS_ALLOW_BRANCH_RESUME=1'

echo ""
echo "=== /commit — behavior contracts ==="
check_fixed commit "first-token awk"          'awk '\''{print $1}'\'''
check_fixed commit "first-token pr check"     '"$FIRST_TOKEN" == "pr"'
check       commit "git status -s"            'git status -s'
check_fixed commit "never -uall"              'never use -uall'
check_fixed commit "pre-staged files check"   'git diff --cached --stat'
check       commit "never add-all"            'stage files by name|Stage only the related files by name'
check_fixed commit "heredoc commit"           'git commit -m "$(cat <<'\''EOF'\'''
check       commit "no-amend after hook fail" 'NEVER.*--amend.*hook|--amend would modify'
check       commit "origin/main for log"      'git log origin/main\.\.HEAD'
check       commit "--watch unreliable"       '--watch.*(exit code is unreliable|UNRELIABLE)'
check_fixed commit "write-landed"             'bash scripts/write-landed.sh'
check       commit "read-only reviewer"       'You are read-only|you are read-only'

echo ""
echo "=== /commit — structural landmarks ==="
check commit "Phase 6 pr subcommand"  '^## Phase 6.*PR'
check commit "Phase 7 land"           '^## Phase 7'

echo ""
echo "=== /do — behavior contracts ==="
check_fixed do "quoted-string escape"         'skip meta-command detection'
check       do "pr extended punctuation"      'extended.*punctuation pattern|extended pattern with.*punctuation'
check       do "task-slug collision suffix"   'date \+%s \| tail -c'
check_fixed do "branch name slug"             'do-${TASK_SLUG}'
check_fixed do "pr worktree path"             '/tmp/${PROJECT_NAME}-do-'
check_fixed do "sanitize-pipeline-id"         'bash scripts/sanitize-pipeline-id.sh'
check_fixed do "pipeline-id format"           'PIPELINE_ID="do.'
check       do "no-echo in main session"      'Do NOT echo.*ZSKILLS_PIPELINE_ID=do'
check_fixed do "rebase before push"           'git rebase origin/main'
check       do "no --fill"                    'never use --fill|NEVER use --fill|not --fill'
check       do "origin/main pr body"          'git log origin/main\.\.HEAD'
check       do "--watch unreliable"           '--watch.*(exit code is unreliable|UNRELIABLE)'
check_fixed do "pr-state-unknown retry"       'pr-state-unknown'
check       do "report-only ci"               '(does NOT|doesn.?t) dispatch fix agents|report-only'

echo ""
echo "=== /do — structural landmarks ==="
check do "Path A PR"        '^### Path A'
check do "Path B Worktree"  '^### Path B'
check do "Path C Direct"    '^### Path C'

echo ""
echo "=== /fix-issues — behavior contracts ==="
check       fix-issues "stop-precedence"            'Takes precedence|takes precedence'
check_fixed fix-issues "landing-default"            'LANDING_MODE="cherry-pick"'
check       fix-issues "direct+main_protected"      'direct mode is incompatible with main_protected'
check_fixed fix-issues "fix branch naming"          'fix/issue-'
check_fixed fix-issues "pr worktree path"           '/tmp/${PROJECT_NAME}-fix-issue-'
check_fixed fix-issues "sprint-id format"           'SPRINT_ID="sprint-'
check_fixed fix-issues "pipeline-id format"         'PIPELINE_ID="fix-issues.'
check_fixed fix-issues "sanitize-pipeline-id"       'bash scripts/sanitize-pipeline-id.sh'
check_fixed fix-issues "recover sprint-id"          'SPRINT_ID="${PIPELINE_ID#fix-issues.'
check       fix-issues "3 agent dispatch cap"       'most 3 worktree agents per message'
check       fix-issues "agent 1-hour timeout"       'Agent timeout: 1 hour|1.hour.*timeout'
check       fix-issues "skip-conflicts protocol"    'cherry-pick CONFLICTS|skip-and-continue'
check       fix-issues "verbatim issue body"        'verbatim issue body|gh issue view'
check       fix-issues "kill cron first on fail"    'Kill the cron FIRST|kill.*cron.*first'
check_fixed fix-issues "pr body Fixes #"            'Fixes #${ISSUE_NUM}'
check       fix-issues "ci timeout 300"             'timeout 300'
check       fix-issues "cross-ref to run-plan ci"   'run-plan.*PR mode landing|See.*run-plan'

echo ""
echo "=== /fix-issues — structural landmarks ==="
check fix-issues "Phase 3"           '^## Phase 3'
check fix-issues "Phase 6 Land"      '^## Phase 6'
check fix-issues "Failure Protocol"  '^## Failure Protocol'

echo ""
echo "=== /verify-changes — RESTRUCTURE-adjacent invariants ==="
check       verify-changes "Scope Assessment header"  '^## Scope Assessment'
check_fixed verify-changes "flag glyph literal"       '⚠️ Flag'
check_fixed verify-changes "faab84b regression anchor" 'faab84b'

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $FAIL_COUNT -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
