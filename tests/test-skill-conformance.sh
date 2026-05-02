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

# check_not <skill> <label> <pattern>
# Inverted `check`: passes when the pattern is ABSENT from the skill tree.
# Used to enforce "no jq binary in scripts", "no || true", etc.
# Pattern is extended regex.
check_not() {
  local skill="$1" label="$2" pattern="$3"
  if grep -rE -e "$pattern" "$REPO_ROOT/skills/$skill/" > /dev/null 2>&1; then
    fail "[$skill] $label" "pattern '$pattern' found but should NOT exist"
  else
    pass "[$skill] $label"
  fi
}

# check_in_file <skill> <relative-path> <label> <pattern>
# Like `check` but scoped to a specific file inside the skill tree.
# Used for "WATCH_EXIT must appear in pr-monitor.sh" etc. — assertions
# that mean "in this specific file" not "anywhere in the skill tree".
check_in_file() {
  local skill="$1" relpath="$2" label="$3" pattern="$4"
  local target="$REPO_ROOT/skills/$skill/$relpath"
  if [ ! -f "$target" ]; then
    fail "[$skill/$relpath] $label" "file does not exist"
    return
  fi
  if grep -E -e "$pattern" "$target" > /dev/null 2>&1; then
    pass "[$skill/$relpath] $label"
  else
    fail "[$skill/$relpath] $label" "$pattern"
  fi
}

# check_not_in_file <skill> <relative-path> <label> <pattern>
# Inverted check_in_file.
check_not_in_file() {
  local skill="$1" relpath="$2" label="$3" pattern="$4"
  local target="$REPO_ROOT/skills/$skill/$relpath"
  if [ ! -f "$target" ]; then
    fail "[$skill/$relpath] $label" "file does not exist"
    return
  fi
  if grep -E -e "$pattern" "$target" > /dev/null 2>&1; then
    fail "[$skill/$relpath] $label" "pattern '$pattern' found but should NOT exist"
  else
    pass "[$skill/$relpath] $label"
  fi
}

# check_executable <skill> <relative-path> <label>
# Asserts a file exists AND has the executable bit set.
check_executable() {
  local skill="$1" relpath="$2" label="$3"
  local target="$REPO_ROOT/skills/$skill/$relpath"
  if [ ! -f "$target" ]; then
    fail "[$skill/$relpath] $label" "file does not exist"
    return
  fi
  if [ -x "$target" ]; then
    pass "[$skill/$relpath] $label"
  else
    fail "[$skill/$relpath] $label" "not executable"
  fi
}

# check_not_in_file_filtered <skill> <relpath> <label> <pattern> <ignore-substring>
# Like check_not_in_file but also strips lines containing
# <ignore-substring> before checking. Used for "no || true except the
# canonical `shift || true` arg-parser idiom" — we want to forbid
# silencing-fallible-op `|| true` while allowing the documented sentinel.
check_not_in_file_filtered() {
  local skill="$1" relpath="$2" label="$3" pattern="$4" ignore="$5"
  local target="$REPO_ROOT/skills/$skill/$relpath"
  if [ ! -f "$target" ]; then
    fail "[$skill/$relpath] $label" "file does not exist"
    return
  fi
  # Strip commented lines AND lines containing the ignore substring,
  # then check for the pattern.
  local hits
  hits=$(grep -nE -e "$pattern" "$target" \
    | grep -v -F "$ignore" \
    | grep -v -E '^[0-9]+:[[:space:]]*#' || true)
  if [ -n "$hits" ]; then
    fail "[$skill/$relpath] $label" "pattern '$pattern' found (excluding '$ignore'): $hits"
  else
    pass "[$skill/$relpath] $label"
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
check       run-plan "test capture redirect"        '\$TEST_OUT/(\$TEST_OUTPUT_FILE|\$\{TEST_OUTPUT_FILE:-\.test-results\.txt\})" 2>&1'
check_fixed run-plan "compute-cron-fire invocation" 'bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/compute-cron-fire.sh"'
check       run-plan "cron tz warning"              'date.*SYSTEM-local|system-local'
# PR_LANDING_UNIFICATION Phase 2 WI 2.7 — `/run-plan` no longer owns the
# inline PR-landing implementation. The following assertions RELOCATED
# to /land-pr's section below: "--watch unreliable", "gh pr checks
# re-check", "timeout 124 handling", "ci log path", "auto-merge expected
# fallback", "pr number from url", "pr number numeric check", "push
# error-check first-time". The `ci-pending pr-ready` assertion was
# REWRITTEN to anchor on /land-pr's WI 1.11 schema (the `pr-ready`
# literal now survives only there, per DA2-6).
#
# `pre-cherry-pick stash` STAYS on /run-plan — it lives in
# modes/cherry-pick.md (cherry-pick mode is out-of-scope for PR
# unification), verified by Round 2 spec.
check       run-plan "pre-cherry-pick stash"        'pre-cherry-pick stash'
# WI 2.7 NEW assertions — verify migration is mechanical:
#   1. /run-plan dispatches /land-pr via the Skill tool
#   2. No inline `gh pr create` — owned by /land-pr's pr-push-and-create.sh
#   3. No inline `gh pr checks --watch` — owned by /land-pr's pr-monitor.sh
#   4. No inline `gh pr merge --auto` — owned by /land-pr's pr-merge.sh
check_fixed run-plan "dispatches /land-pr"          'land-pr'
check_not   run-plan "no inline gh pr create"       'gh pr create'
check_not   run-plan "no inline gh pr checks --watch" 'gh pr checks.*--watch'
check_not   run-plan "no inline gh pr merge --auto"  'gh pr merge.*--auto'
check_fixed run-plan "write-landed invocation"      'bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh"'
check_fixed run-plan "pr-mode bookkeeping"          'PR-mode bookkeeping'
check_fixed run-plan "post-run-invariants"          'bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/post-run-invariants.sh"'
check_fixed run-plan "final-verify marker glob"     'requires.verify-changes.final.'
# PR-mode read-authority (the bug caught during CANARY10 re-run): when
# LANDING_MODE=pr and a feature-branch worktree exists, plan reads MUST
# come from the worktree — main's copy is stale until squash-merge. Step 0
# and Parse Plan read from $PLAN_FILE_FOR_READ, not raw $PLAN_FILE.
check_fixed run-plan "read-auth: PR worktree path"  'PR_WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"'
check_fixed run-plan "read-auth: feature-branch branch" 'PLAN_FILE_FOR_READ="$PR_WORKTREE_PATH/$PLAN_FILE"'
check_fixed run-plan "read-auth: main fallback"     'PLAN_FILE_FOR_READ="$MAIN_ROOT/$PLAN_FILE"'
# PR-body progress sync (issue #60): PR mode opens the PR once in Phase 6
# and used to never revisit the body, leaving the progress checklist frozen
# at Phase 1. The fix wraps the PR body's progress section in HTML-comment
# markers at open time (modes/pr.md) and adds a Phase 4 splice step
# (SKILL.md) that rewrites only the marker-enclosed region, preserving
# user-authored prose outside. Conformance assertions:
#   1. Both markers exist in the PR body template.
#   2. Phase 4 invokes gh pr edit for the body sync.
#   3. Phase 4 splices between the same two markers.
#   4. Phase 4 emits the NOTICE-on-missing-markers fallback text (skipping
#      rather than erroring), preserving graceful behavior for PRs not
#      opened by /run-plan.
check_fixed run-plan "pr body: start marker"          '<!-- run-plan:progress:start -->'
check_fixed run-plan "pr body: end marker"            '<!-- run-plan:progress:end -->'
check_fixed run-plan "phase4: gh pr edit body sync"   'gh pr edit "$PR_NUMBER" --body'
check_fixed run-plan "phase4: splice between markers" '(.*$START_MARKER)(.*)($END_MARKER.*)'
check       run-plan "phase4: NOTICE on missing markers" 'markers not found.*expected for PRs not opened by /run-plan'
# Test-command resolution (caught by CANARY10 re-run — verifier defaulted to
# a template file because no skill resolved testing.full_cmd). Both /run-plan
# and /verify-changes MUST have the three-case decision tree: config → use,
# test-infra-exists → fail, no-infra → skipped + explicit report note.
check_fixed run-plan "test-cmd: config.full_cmd read" 'full_cmd'
check_fixed run-plan "test-cmd: TEST_MODE=config"     'TEST_MODE="config"'
check_fixed run-plan "test-cmd: TEST_MODE=skipped"    'TEST_MODE="skipped"'
check_fixed run-plan "test-cmd: misconfig refusal"    'test infra detected but testing.full_cmd is empty'
check       run-plan "test-cmd: no raw npm run test:all in exec paths" \
  '^[[:space:]]*>?[[:space:]]*\$FULL_TEST_CMD'
# Same contract for /verify-changes.
check_fixed verify-changes "test-cmd: config.full_cmd read" 'full_cmd'
check_fixed verify-changes "test-cmd: TEST_MODE=config"     'TEST_MODE="config"'
check_fixed verify-changes "test-cmd: TEST_MODE=skipped"    'TEST_MODE="skipped"'
check_fixed verify-changes "test-cmd: misconfig refusal"    'test infra detected'
check_fixed verify-changes "test-cmd: skipped report text"  'Tests: skipped — no test infra'

echo ""
echo "=== /run-plan — structural landmarks ==="
check run-plan "Phase 5b header"    '^## Phase 5b'
check run-plan "Phase 5c header"    '^## Phase 5c'
check run-plan "Phase 6 header"     '^## Phase 6'
check run-plan "Failure Protocol"   '^## Failure Protocol'

echo ""
echo "=== /run-plan — shell idioms ==="
check_fixed run-plan "create-worktree invocation" 'bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh"'
check_fixed run-plan "pr mode --allow-resume"     '--allow-resume'

echo ""
echo "=== /commit — behavior contracts ==="
check_fixed commit "first-token awk"          'awk '\''{print $1}'\'''
check_fixed commit "first-token pr check"     '"$FIRST_TOKEN" == "pr"'
check       commit "git status -s"            'git status -s'
check_fixed commit "never -uall"              'never use -uall'
check_fixed commit "pre-staged files check"   'git diff --cached --stat'
check       commit "never add-all"            'stage files by name|Stage only the related files by name'
check_fixed commit "quoted heredoc body"      '-m "$(cat <<'\''EOF'\'''
check       commit "no-amend after hook fail" 'NEVER.*--amend.*hook|--amend would modify'
check       commit "origin/main for log"      'git log origin/main\.\.HEAD'
# PR_LANDING_UNIFICATION Phase 3 WI 3.4 — /commit pr no longer owns the
# inline PR-landing implementation. The following assertions RELOCATED:
#   - "--watch unreliable" → /land-pr's section (line ~391, already there).
#   - "step6: past-failure preamble" → /land-pr's section (line ~411,
#     upgraded to the verbatim `Past failure.*PR #131|skipped Step 6 on PR
#     #131` regex per WI 3.4).
# REMOVED: "step6: poll-ci.sh invocation" — poll-ci.sh was deleted in
# WI 3.5a; pr-monitor.sh in /land-pr is the canonical successor.
check_fixed commit "write-landed"             'bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh"'
# WI 3.4 NEW: verify modes/pr.md now dispatches /land-pr.
check_fixed commit "modes/pr.md dispatches /land-pr" 'land-pr'
check       commit "read-only reviewer"       'You are read-only|you are read-only'
# Config-driven default mode (issue #56): /commit with no explicit mode
# token must consult execution.landing in .claude/zskills-config.json
# instead of always defaulting to commit-only. Explicit `pr` (first
# token), `push` (anywhere), or `land` (anywhere) override the config.
# A config of `cherry-pick` is rejected as misuse (the `land` subcommand
# is the cherry-pick flow, not a default-mode selector).
check_fixed commit "default-mode: landing config read"   'execution.landing'
check_fixed commit "default-mode: bash-regex landing"    '\"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"'
check_fixed commit "default-mode: explicit-mode guard"   'HAS_EXPLICIT_MODE'
check_fixed commit "default-mode: push|land anywhere"    '(push|land)'
check_fixed commit "default-mode: pr → PR mode"          'DEFAULT_MODE="pr"'
check_fixed commit "default-mode: direct → commit-only"  'direct|"")'
check       commit "default-mode: cherry-pick rejected"  'cherry-pick.*not a valid default|cherry-pick.*NOT a default-mode'
check       commit "default-mode: no jq dependency"      'Bash regex only|no jq|no external JSON'

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
check_fixed do "sanitize-pipeline-id"         'bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"'
check_fixed do "pipeline-id format"           'PIPELINE_ID="do.'
# Landing-mode resolution: /do must detect pr/direct/worktree flags,
# fall back to execution.landing in zskills-config, and enforce the
# direct+main_protected guard. Mirrors /run-plan and /fix-issues.
check_fixed do "landing arg: pr"              'ARG_LANDING="pr"'
check_fixed do "landing arg: direct"          'ARG_LANDING="direct"'
check_fixed do "landing arg: worktree"        'ARG_LANDING="worktree"'
check_fixed do "landing config read"          'execution.landing'
check_fixed do "landing config: cherry-pick"  'cherry-pick) LANDING_MODE="worktree"'
check       do "landing fallback direct"      'LANDING_MODE="direct"'
check       do "direct+main_protected guard"  'direct mode is incompatible with main_protected'
check       do "no-echo in main session"      'Do NOT echo.*ZSKILLS_PIPELINE_ID=do'
# PR_LANDING_UNIFICATION Phase 3 WI 3.9 — /do pr no longer owns the
# inline PR-landing implementation. The following assertions RELOCATED:
#   - "rebase before push" (`git rebase origin/main`) → /land-pr
#     (now lives in scripts/pr-rebase.sh; literal no longer in /do).
#   - "--watch unreliable" → /land-pr's section (line ~391, already there).
# REMOVED: "report-only ci" — its INTENT is now incorrect because Phase 3
# is a drift fix that ADDS fix-cycle to /do pr; replaced with
# "modes/pr.md dispatches /land-pr".
check       do "no --fill"                    'never use --fill|NEVER use --fill|not --fill'
check       do "origin/main pr body"          'git log origin/main\.\.HEAD'
# WI 3.9 STAYS: `pr-state-unknown` token still referenced in /do's
# caller-loop wrapper (Step A8 schema-harmonization note explains it
# is now emitted by /land-pr's status-mapping table).
check_fixed do "pr-state-unknown retry"       'pr-state-unknown'
# WI 3.9 NEW: verify modes/pr.md now dispatches /land-pr.
check_fixed do "modes/pr.md dispatches /land-pr" 'land-pr'
# WI 3.7 regression guard: `gh pr create` must NOT appear anywhere in
# /do (SKILL.md or modes/) — that primitive moved to /land-pr's
# pr-push-and-create.sh. Future drift (e.g., re-introducing inline `gh pr
# create` for a bypass path) is caught here.
check_not   do "no inline gh pr create"       'gh pr create'
check_not   do "no inline gh pr checks --watch" 'gh pr checks.*--watch'

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
check_fixed fix-issues "sanitize-pipeline-id"       'bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"'
check_fixed fix-issues "recover sprint-id"          'SPRINT_ID="${PIPELINE_ID#fix-issues.'
check       fix-issues "3 agent dispatch cap"       'most 3 worktree agents per message'
check       fix-issues "agent 1-hour timeout"       'Agent timeout: 1 hour|1.hour.*timeout'
check       fix-issues "skip-conflicts protocol"    'cherry-pick CONFLICTS|skip-and-continue'
check       fix-issues "verbatim issue body"        'verbatim issue body|gh issue view'
check       fix-issues "kill cron first on fail"    'Kill the cron FIRST|kill.*cron.*first'
check_fixed fix-issues "pr body Fixes #"            'Fixes #${ISSUE_NUM}'
# PR_LANDING_UNIFICATION Phase 4 WI 4.6 — /fix-issues pr no longer owns the
# inline PR-landing implementation. The following assertions changed:
#   - "ci timeout 300" → REMOVED (WI 4.2 drops the 300s special case;
#     /land-pr's default 600s applies).
#   - "cross-ref to run-plan ci" → REMOVED (CI logic now lives in
#     /land-pr, not /run-plan; the cross-ref is obsolete).
#   - "auto-merge AUTO guard" → RELOCATED to /land-pr's pr-merge.sh
#     (line 67 uses `if [ "$AUTO_FLAG" != "true" ]`).
#   - "ci poll always runs in pr.md" → REWRITTEN as
#     "modes/pr.md dispatches /land-pr per-issue" — the literal
#     comment-text pattern is brittle; assertion now verifies that
#     /fix-issues unconditionally dispatches /land-pr per-issue
#     (regardless of AUTO).
check       fix-issues "auto-gating prose"          'Auto-flag gating depends on landing mode|gated on \$AUTO'
check_fixed fix-issues "pr ci+fix-cycle always run" 'CI polling, and the fix cycle ALL run regardless of'
check_fixed fix-issues "only merge gated on auto"   'Only `gh pr merge --auto --squash` is gated on `auto`'
check_fixed fix-issues "cherry-pick defers to fix-report" 'Cherry-picks land via `/fix-report`'
check       fix-issues "direct requires auto"       'never run that without|explicit `auto` consent'
# WI 4.6 NEW: verify modes/pr.md now dispatches /land-pr per-issue.
check_fixed fix-issues "modes/pr.md dispatches /land-pr per-issue" 'land-pr'
# WI 4.6 regression guard: `gh pr create` and `gh pr checks --watch`
# must NOT appear anywhere in /fix-issues — those primitives moved to
# /land-pr's pr-push-and-create.sh / pr-monitor.sh. Future drift (e.g.,
# re-introducing inline `gh pr create` for a bypass path) is caught
# here. Mirrors the same regression guards on /commit (line ~316-317)
# and /do (line ~316-317). The `gh pr merge --auto --squash` text
# remains in prose only — see "only merge gated on auto" assertion
# above; the executable invocation now lives in /land-pr's pr-merge.sh.
check_not   fix-issues "no inline gh pr create"       'gh pr create'
check_not   fix-issues "no inline gh pr checks --watch" 'gh pr checks.*--watch'
# WI 4.6 RELOCATE: the `if [ "$AUTO_FLAG" != "true" ]` literal guard
# now lives in /land-pr's pr-merge.sh (Phase 1B WI 1.6). Verify it
# stays there.
check_in_file land-pr scripts/pr-merge.sh "auto-merge AUTO_FLAG guard" 'if \[ "\$AUTO_FLAG" != "true" \]; then'

echo ""
echo "=== /fix-issues — structural landmarks ==="
check fix-issues "Phase 3"           '^## Phase 3'
check fix-issues "Phase 6 Land"      '^## Phase 6'
check fix-issues "Failure Protocol"  '^## Failure Protocol'

echo ""
echo "=== /quickfix — behavior contracts (PR_LANDING_UNIFICATION Phase 5) ==="
# WI 5.6 — verify Phase 7 migration is mechanical:
#   1. /quickfix dispatches /land-pr via the Skill tool (CI poll +
#      fix-cycle now present as additive coverage on top of the post-#151
#      triage + plan-review gates).
#   2. No inline `gh pr create` — owned by /land-pr's pr-push-and-create.sh.
#   3. No "Fire-and-forget" prose — replaced by the new full-lifecycle
#      description (`triage → review → commit → push → PR → CI poll →
#      fix cycle`). Note: any `--force` or `--fill` references elsewhere
#      in the skill are unaffected; only the literal "Fire-and-forget"
#      prose is removed.
check_fixed quickfix "Phase 7 dispatches /land-pr" 'land-pr'
check_not   quickfix "no inline gh pr create"      'gh pr create'
check_not   quickfix "no fire-and-forget literal"  'Fire-and-forget'

echo ""
echo "=== Cross-skill PR-landing tripwires (PR_LANDING_UNIFICATION Phase 6 WI 6.1) ==="
# Drift-prevention assertions catching any future re-introduction of inline
# PR-landing primitives outside /land-pr. Each historical drift bug below
# had to be patched reactively — these tripwires fail-closed at conformance
# time so a regression never ships.
#
# Drift-bug rationale (WI 6.3):
#   - 87af82a — `gh pr checks --watch` exit code unreliable; needed bare
#     re-check after watch exits non-zero. /land-pr's pr-monitor.sh is the
#     canonical resolution; inline copies in callers re-introduce the bug.
#   - 1de3049 — duplicate `gh pr create` invocation after rebase failure;
#     pr-push-and-create.sh handles single-shot creation with stderr
#     capture. Inline copies risked retry-then-conflict.
#   - 175e4aa — auto-merge stderr text varies between gh versions; only
#     pr-merge.sh's allow-list of benign stderr strings handles this
#     correctly. Inline `gh pr merge` calls without that allow-list
#     spuriously fail otherwise-successful merges.
#   - b904cef — agent skipped a step on PR #131 push, treated inline bash
#     as suggestion-prose, did one snapshot poll. The /land-pr dispatch
#     contract makes this skip-class impossible: the caller invokes the
#     skill, which executes deterministically.
#
# Pattern design (per spec WI 6.1, R6-2/DA2-2):
# Anchor each invocation pattern to start-of-line so prose mentions
# (backtick-quoted substrings, "Manual fallback:" echoes, list-marker
# prefixes, "**Only \`gh pr merge --auto --squash\`** is gated" gating
# prose) survive while live invocations are caught.

# --- Cross-skill grep helpers ---

# cross_check_no_invocation <label> <pattern> <root>
# Greps <root> for <pattern> recursively; passes if zero hits OUTSIDE
# skills/land-pr/ (or .claude/skills/land-pr/ for the mirror root). Only
# the start-of-line-anchored invocation patterns from WI 6.1 are passed
# in — prose mentions don't match. The exclusion uses fixed-string
# `land-pr/` so both source and mirror trees work.
cross_check_no_invocation() {
  local label="$1" pattern="$2" root="$3"
  local hits
  hits=$(grep -rEln -e "$pattern" "$root/" | grep -v 'land-pr/')
  if [ -z "$hits" ]; then
    pass "[cross-skill] $label"
  else
    fail "[cross-skill] $label" "live invocation outside /land-pr: $(echo "$hits" | tr '\n' ' ')"
  fi
}

# --- WI 6.1 (a) — No inline `gh pr create` invocations ---
# Pattern: start-of-line, optional `if [!]`/`VAR=`/`$(` invocation
# prefixes. Excludes prose backtick-mentions and bullet-list mentions.
cross_check_no_invocation "no inline gh pr create (skills/)" \
  '^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr create\b' \
  "$REPO_ROOT/skills"
cross_check_no_invocation "no inline gh pr create (.claude/skills/)" \
  '^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr create\b' \
  "$REPO_ROOT/.claude/skills"

# --- WI 6.1 (b) — No inline `gh pr checks --watch` invocations ---
# Pattern: start-of-line with optional `timeout N` wrapper. Excludes
# prose like backtick-quoted `timeout 600 gh pr checks --watch` and
# bullet-list discussion of the unreliable-exit behavior.
cross_check_no_invocation "no inline gh pr checks --watch (skills/)" \
  '^[[:space:]]*(timeout[[:space:]]+[0-9]+[[:space:]]+)?gh pr checks\b.*--watch\b' \
  "$REPO_ROOT/skills"
cross_check_no_invocation "no inline gh pr checks --watch (.claude/skills/)" \
  '^[[:space:]]*(timeout[[:space:]]+[0-9]+[[:space:]]+)?gh pr checks\b.*--watch\b' \
  "$REPO_ROOT/.claude/skills"

# --- WI 6.1 (c) — No inline `gh pr merge` invocations ---
# Pattern: start-of-line, optional `if [!]`/`VAR=`/`$(` invocation
# prefixes. Excludes prose like `**Only \`gh pr merge --auto --squash\`
# is gated on \`auto\`**` (backtick-prefix, not whitespace-prefix).
cross_check_no_invocation "no inline gh pr merge (skills/)" \
  '^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr merge\b' \
  "$REPO_ROOT/skills"
cross_check_no_invocation "no inline gh pr merge (.claude/skills/)" \
  '^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr merge\b' \
  "$REPO_ROOT/.claude/skills"

# --- WI 6.1 (d) — All 5 callers dispatch /land-pr ---
# Substring match suffices because `land-pr` only appears in dispatch
# contexts inside the caller files (verified during Phase 2-5 migrations).
# These checks duplicate the per-skill assertions above (run-plan,
# commit, do, fix-issues, quickfix already each have their own
# `dispatches /land-pr` check) but consolidate them as a single
# cross-skill drift-prevention claim.
LAND_PR_CALLERS=(
  "skills/run-plan/modes/pr.md"
  "skills/commit/modes/pr.md"
  "skills/do/modes/pr.md"
  "skills/fix-issues/modes/pr.md"
  "skills/quickfix/SKILL.md"
)
ALL_CALLERS_OK=1
for caller in "${LAND_PR_CALLERS[@]}"; do
  if [ ! -f "$REPO_ROOT/$caller" ]; then
    fail "[cross-skill] caller exists: $caller" "file does not exist"
    ALL_CALLERS_OK=0
  elif ! grep -q -F 'land-pr' "$REPO_ROOT/$caller"; then
    fail "[cross-skill] caller dispatches /land-pr: $caller" "no 'land-pr' substring found"
    ALL_CALLERS_OK=0
  fi
done
if [ "$ALL_CALLERS_OK" -eq 1 ]; then
  pass "[cross-skill] all 5 callers reference /land-pr (dispatch present)"
fi

# --- WI 6.1 (e) — Orchestrator-level dispatch verification ---
# The /land-pr Skill-tool invocation MUST appear at top-level prose, NOT
# inside an Agent prompt block. The dispatch contract is documented in
# /land-pr/SKILL.md and load-bearing decision #6 of the plan. Heuristic:
# locate the dispatch line (matches `Skill:[[:space:]]*\{[[:space:]]*skill:`
# with `land-pr`); verify the surrounding ±15 lines do NOT contain
# start-of-line `Agent:`, `prompt:`, or `dispatch.*agent` markers.
#
# Per R6-13 / R3-4: all three alternatives are uniformly start-of-line-
# anchored to avoid prose false-matches. Documented residual limitation
# (WI 6.1): a prose paragraph that happens to start a line with "Agent:"
# can still false-fail; the implementer can refine the pattern as needed.
NESTED_AGENT_RE='^[[:space:]]*(Agent:|prompt:|dispatch.*agent)'
ORCH_DISPATCH_FAIL=0
for caller in "${LAND_PR_CALLERS[@]}"; do
  caller_path="$REPO_ROOT/$caller"
  [ ! -f "$caller_path" ] && continue
  # Locate the `Skill: { skill: "land-pr" ... }` dispatch line. Matches
  # both bare and indented forms.
  dispatch_line=$(grep -nE 'Skill:[[:space:]]*\{[[:space:]]*skill:[[:space:]]*"land-pr"' "$caller_path" | head -1 | cut -d: -f1)
  if [ -z "$dispatch_line" ]; then
    fail "[cross-skill] orchestrator dispatch found in $caller" "no Skill:{skill:\"land-pr\"} line"
    ORCH_DISPATCH_FAIL=1
    continue
  fi
  win_start=$((dispatch_line - 15))
  win_end=$((dispatch_line + 15))
  [ "$win_start" -lt 1 ] && win_start=1
  if sed -n "${win_start},${win_end}p" "$caller_path" | grep -qE -e "$NESTED_AGENT_RE"; then
    fail "[cross-skill] /land-pr dispatched at orchestrator level in $caller" \
      "nested-Agent marker (Agent:/prompt:/dispatch.*agent) found within ±15 lines of dispatch line $dispatch_line"
    ORCH_DISPATCH_FAIL=1
  fi
done
if [ "$ORCH_DISPATCH_FAIL" -eq 0 ]; then
  pass "[cross-skill] /land-pr dispatched at orchestrator level in all 5 callers (no nested-Agent markers within ±15 lines)"
fi

echo ""
echo "=== /verify-changes — RESTRUCTURE-adjacent invariants ==="
check       verify-changes "Scope Assessment header"  '^## Scope Assessment'
check_fixed verify-changes "flag glyph literal"       '⚠️ Flag'
check_fixed verify-changes "faab84b regression anchor" 'faab84b'

echo ""
echo "=== /land-pr — Phase 1B drift tripwire (PR_LANDING_UNIFICATION) ==="
# These assertions back-fill the moves from /run-plan's existing inline
# assertions to /land-pr (per Phase 2 WI 2.7). Once 1B lands, conformance
# enforces the no-regression contract for Phases 2–5 caller migrations.

# --- Frontmatter / argument-hint ---
check_fixed land-pr "frontmatter name"            'name: land-pr'
check_fixed land-pr "argument-hint exists"        'argument-hint:'
# References to each of the 4 scripts in SKILL.md (separate assertions
# because the references span many lines and a single regex match is
# brittle):
check_fixed land-pr "references pr-rebase.sh"          'pr-rebase.sh'
check_fixed land-pr "references pr-push-and-create.sh" 'pr-push-and-create.sh'
check_fixed land-pr "references pr-monitor.sh"         'pr-monitor.sh'
check_fixed land-pr "references pr-merge.sh"           'pr-merge.sh'

# --- Result-file safety contract ---
check_fixed land-pr "result-file contract var"   '$RESULT_FILE'
check       land-pr "validate_result_value defined" 'validate_result_value'

# --- WATCH_EXIT (DA2-5) ---
# WATCH_EXIT must be the executable variable name. WATCH_RC is the older
# name from poll-ci.sh — it must not appear in any executable line in
# pr-monitor.sh. Comments DOCUMENT the migration (line 15 of pr-monitor.sh
# explicitly says `# - Uses WATCH_EXIT (not WATCH_RC)`); the comment-strip
# regex `^[^#]*` lets the documentation stand while still failing if any
# executable line uses WATCH_RC.
check_in_file     land-pr scripts/pr-monitor.sh "WATCH_EXIT (not WATCH_RC)" 'WATCH_EXIT'
check_not_in_file land-pr scripts/pr-monitor.sh "WATCH_RC absent in executable lines" '^[^#]*WATCH_RC'

# --- Monitor: --watch + bare re-check pattern ---
check_fixed land-pr "monitor uses --watch"     'gh pr checks "$PR_NUMBER" --watch'
check       land-pr "monitor bare re-check"    'gh pr checks "\$PR_NUMBER" >/dev/null'

# --- PR_NUMBER from URL via parameter expansion (no second gh pr view) ---
check       land-pr "PR_NUMBER from URL not gh pr view" '\$\{[A-Z_]*##\*/\}'

# --- WI 2.7 RELOCATED from /run-plan (post-Phase-2 migration) ---
# Per plan: when /run-plan migrates to dispatch /land-pr, the inline
# assertions targeting CI polling, --watch handling, the fallback
# re-check, the auto-merge expected-fallback wording, the PR_URL→PR_NUMBER
# extraction, and the push error-check first-time pattern all RELOCATE
# here because the implementations now live in /land-pr's
# scripts/pr-monitor.sh, scripts/pr-merge.sh, and scripts/pr-push-and-create.sh.
check       land-pr "--watch unreliable"           '--watch.*(exit code is unreliable|UNRELIABLE)'
check_fixed land-pr "gh pr checks re-check"        'gh pr checks "$PR_NUMBER"'
check_fixed land-pr "timeout 124 handling"         'WATCH_EXIT" -eq 124'
# `pr-ready` literal — REWRITTEN per DA2-6 against /land-pr's WI 1.11
# canonical .landed schema and WI 1.12 status mapping table (rows 4, 5,
# 7, 9, 10 produce pr-ready). After WI 2.2 deletes /run-plan's inline
# block, the literal survives only here.
check_fixed land-pr "pr-ready status mapping"      'pr-ready'
# CI log path — /land-pr's pr-monitor.sh names it differently from the
# old /run-plan inline path (`/tmp/ci-failure-`). Anchor on the new path.
check       land-pr "ci log path"                  '/tmp/land-pr-ci-log-'
check       land-pr "auto-merge expected fallback" 'auto-merge enabled|expected.{0,15}auto-merge'
check_fixed land-pr "pr number from url"           'PR_NUMBER="${PR_URL##*/}"'
check       land-pr "pr number numeric check"      'PR_NUMBER" =~ \^\[0-9\]\+\$'
check       land-pr "push error-check first-time"  'if ! git push -u origin'

# --- BRANCH_SLUG derivation (foundation bug fix from Phase 1A) ---
check_fixed land-pr "BRANCH_SLUG derivation"  'BRANCH_SLUG'

# --- PR #131 past-failure preamble (issue #133; WI 3.4 RELOCATED from /commit) ---
# Spec verbatim (WI 3.4): the regex MUST anchor on the substantive failure
# wording so paraphrase drift trips the assertion.
check land-pr "PR #131 past-failure preamble" 'Past failure.*PR #131|skipped Step 6 on PR #131'

# --- Caller loop: allow-list parser pattern ---
check land-pr "allow-list parser key set" 'STATUS\|PR_URL\|PR_NUMBER'

# --- Failure modes catalog exists (WI 1B.1) ---
check_fixed land-pr "failure-modes catalog exists" 'The 10 failure modes'

# --- 4 scripts exist + executable ---
check_executable land-pr scripts/pr-rebase.sh           "pr-rebase.sh executable"
check_executable land-pr scripts/pr-push-and-create.sh  "pr-push-and-create.sh executable"
check_executable land-pr scripts/pr-monitor.sh          "pr-monitor.sh executable"
check_executable land-pr scripts/pr-merge.sh            "pr-merge.sh executable"

# --- No `jq` binary in scripts (gh ... --jq flag is OK; standalone jq is forbidden) ---
# Per the plan: anchor on `^[[:space:]]*jq ` so `gh --jq '.foo'` flag use is
# still allowed. Scope to scripts/ only — references/ may discuss jq in prose.
check_not_in_file land-pr scripts/pr-rebase.sh          "no jq binary"          '^[[:space:]]*jq '
check_not_in_file land-pr scripts/pr-push-and-create.sh "no jq binary"          '^[[:space:]]*jq '
check_not_in_file land-pr scripts/pr-monitor.sh         "no jq binary"          '^[[:space:]]*jq '
check_not_in_file land-pr scripts/pr-merge.sh           "no jq binary"          '^[[:space:]]*jq '

# --- No `|| true` in scripts on FALLIBLE operations.
# Per the four scripts' arg-parser idiom, `shift || true` is the
# canonical no-more-args sentinel inside the `while [ $# -gt 0 ]` loop —
# intentional, not a silenced fallible op (the next iteration's
# `[ $# -gt 0 ]` reads the state shift produced). The filtered-helper
# strips lines containing `shift || true` before checking, so that the
# canonical idiom is allowed but any other `|| true` fails the assertion.
check_not_in_file_filtered land-pr scripts/pr-rebase.sh          "no || true on fallible ops" '\|\| true' 'shift || true'
check_not_in_file_filtered land-pr scripts/pr-push-and-create.sh "no || true on fallible ops" '\|\| true' 'shift || true'
check_not_in_file_filtered land-pr scripts/pr-monitor.sh         "no || true on fallible ops" '\|\| true' 'shift || true'
check_not_in_file_filtered land-pr scripts/pr-merge.sh           "no || true on fallible ops" '\|\| true' 'shift || true'

# --- No `2>/dev/null` on fallible paths in scripts.
# Anchor on `^[^#]*` to skip the prose comments at pr-monitor.sh:12-13
# (which DOCUMENT the past failure of using 2>/dev/null in poll-ci.sh).
# Documented exemption (per SKILL.md step 2): the resume-mode `gh pr view`
# PR_URL recovery in SKILL.md uses `2>/dev/null` because empty-PR_URL is an
# explicit handled outcome. That exemption lives in SKILL.md, NOT in any
# script under scripts/ — so per-script the assertion is unconditional.
check_not_in_file land-pr scripts/pr-rebase.sh          "no 2>/dev/null on fallible ops" '^[^#]*2>/dev/null'
check_not_in_file land-pr scripts/pr-push-and-create.sh "no 2>/dev/null on fallible ops" '^[^#]*2>/dev/null'
check_not_in_file land-pr scripts/pr-monitor.sh         "no 2>/dev/null on fallible ops" '^[^#]*2>/dev/null'
check_not_in_file land-pr scripts/pr-merge.sh           "no 2>/dev/null on fallible ops" '^[^#]*2>/dev/null'

# --- Caller loop pattern lives in references ---
check_in_file land-pr references/caller-loop-pattern.md "caller loop allow-list keys" \
  'STATUS\|PR_URL\|PR_NUMBER'
# Defense-in-depth: caller pattern must explicitly forbid `source` of the
# result file. Two literal landmarks (defense + parser-rationale section).
check_fixed land-pr 'never source: contract bullet'   'Never `source`'
check_fixed land-pr 'never source: parser rationale'  'allow-list parser, not `source`'

# --- Caller pattern: no source-based result parsing ---
check_not land-pr "no source-based result parsing in caller pattern" \
  'source[[:space:]]+.*RESULT_FILE|^\.[[:space:]]+.*RESULT_FILE'

echo ""
echo "=== /update-zskills — Step C / C.9 / D contract (DRIFT_ARCH_FIX Phase 2) ==="
# Step C is the agent-driven settings.json merge — Read+Edit, never Write-from-template.
# Step C.9 is the hook-rename migration table (initially empty, append-only).
# Step D is the --rerender subcommand for CLAUDE.md regeneration.
# These assertions guard the SKILL.md contract; they do NOT execute the skill.

# WI 2.7.1 — Step C says "Read + Edit", never "Write the whole file".
check_fixed update-zskills "Step C: Read + Edit (agent-driven)" \
  'surgical'
check       update-zskills "Step C: Read + Edit terms appear" \
  '`Read`.*`Edit`|Read. .*Edit.'
check_fixed update-zskills "Step C: never Write-from-template"      'never `Write`-from-template'

# WI 2.7.2 — Canonical zskills-owned triples for all 5 rows (3 PreToolUse + 2 PostToolUse).
check_fixed update-zskills "Step C triples: PreToolUse Bash block-unsafe-generic" \
  'PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh"`'
check_fixed update-zskills "Step C triples: PreToolUse Bash block-unsafe-project" \
  'PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-project.sh"`'
check_fixed update-zskills "Step C triples: PreToolUse Agent block-agents" \
  'PreToolUse   | Agent   | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh"`'
check_fixed update-zskills "Step C triples: PostToolUse Edit warn-config-drift" \
  'PostToolUse  | Edit    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"`'
check_fixed update-zskills "Step C triples: PostToolUse Write warn-config-drift" \
  'PostToolUse  | Write   | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"`'

# WI 2.7.3 — Preserve rule: never overwrite, never reorder top-level keys.
check_fixed update-zskills "Step C preserve: never overwrite"         'never overwrite'
check_fixed update-zskills "Step C preserve: never reorder top-level" 'never reorder top-level keys'
check_fixed update-zskills "Step C preserve: foreign entries preserved" \
  'preserved untouched'

# WI 2.7.4 — Preview-and-confirm convention (mirrors Step B).
check_fixed update-zskills "Step C preview-and-confirm"               'Preview and confirm before any `Edit`'
check       update-zskills "Step C preview mentions Step B parity" \
  'Mirrors the Step B CLAUDE.md append convention'
check_fixed update-zskills "Step C report line"                       'registered N hook entries'

# WI 2.7.5 — Step C.9 rename subsection exists, is initially empty, documents format.
check       update-zskills "Step C.9 subsection header" \
  '^#### Step C\.9 — Hook renames'
check_fixed update-zskills "Step C.9 initially empty"                 '# (none yet)'
check_fixed update-zskills "Step C.9 append-only"                     'append-only'
check_fixed update-zskills "Step C.9 idempotent"                      'idempotent'
check_fixed update-zskills "Step C.9 runs before main merge"          'run BEFORE the main Step C merge'
check_fixed update-zskills "Step C.9 row format documented"           'old_command: bash'
check_fixed update-zskills "Step C.9 contribution instructions"       'ships the rename'

# WI 4.x — Step B renders into .claude/rules/zskills/managed.md (zskills-owned).
check       update-zskills "Step B header: render rules file" \
  '^#### Step B — Render zskills-managed rules file'
check_fixed update-zskills "Step B: target path managed.md" \
  '.claude/rules/zskills/managed.md'
check_fixed update-zskills "Step B: ownership rule" \
  'zskills owns `.claude/rules/zskills/` in full'
check_fixed update-zskills "Step B: root CLAUDE.md is user's" \
  'root `./CLAUDE.md` is theirs exclusively'
# WI 4.4 — Migration sub-step: root CLAUDE.md detection + backup + NOTICE.
check       update-zskills "Step B: migration sub-step header" \
  '^\*\*Migration sub-step'
check_fixed update-zskills "Step B: migration ±2 line context" \
  '±2-line'
check_fixed update-zskills "Step B: migration backup path" \
  './CLAUDE.md.pre-zskills-migration'
check_fixed update-zskills "Step B: migration NOTICE stderr" \
  'NOTICE: Migrated zskills content'
check_fixed update-zskills "Step B: migration idempotent no backup overwrite" \
  'Never overwrite a prior backup'

# WI 4.2 — Step D --rerender section: simple full-file rewrite, rc=0/rc=1 only.
check       update-zskills "Step D header" \
  '^### Step D — --rerender'
check_fixed update-zskills "Step D: --rerender trigger"               '`/update-zskills --rerender`'
check_fixed update-zskills "Step D: full-file rewrite scope" \
  'full-file rewrite of `.claude/rules/zskills/managed.md`'
check_fixed update-zskills "Step D: root CLAUDE.md never touched" \
  'Root `./CLAUDE.md` is never touched by `--rerender`'
check_fixed update-zskills "Step D: exit 0 success" \
  'Re-render complete'
check_fixed update-zskills "Step D: exit 1 template missing" \
  'CLAUDE_TEMPLATE.md missing or unreadable'
# Negative assertion — the byte-compare / .new artifacts MUST be gone.
if grep -nE 'CLAUDE\.md\.new|byte-compare|Agent Rules.*demarcation|boundary-detection' \
  "$REPO_ROOT/skills/update-zskills/SKILL.md" > /dev/null 2>&1; then
  fail "[update-zskills] WI4.2: Step D still references byte-compare / .new / boundary" \
    "CLAUDE.md.new or byte-compare language still present"
else
  pass "[update-zskills] WI4.2: no byte-compare / .new / boundary references in SKILL.md"
fi

# WI 2.1 — Step C hook-gap block no longer fills migrated placeholders.
# (block-unsafe-project.sh should say "No install-time placeholder fill needed".)
check_fixed update-zskills "WI2.1: block-unsafe-project runtime-read" \
  'reads `testing.unit_cmd`, `testing.full_cmd`,'
check_fixed update-zskills "WI2.1: E2E/BUILD still allowed" \
  '{{E2E_TEST_CMD}}'
# Negative assertion — the four migrated placeholders must not appear as
# "fill" instructions anywhere in Step C's hook-gap section.
# (We allow them in migration-mapping tables, just not as "fill in X from Y".)
if grep -nE 'fill in.*\{\{UNIT_TEST_CMD\}\}|fill in.*\{\{FULL_TEST_CMD\}\}|fill in.*\{\{UI_FILE_PATTERNS\}\}|fill in.*\{\{MAIN_REPO_PATH\}\}' \
  "$REPO_ROOT/skills/update-zskills/SKILL.md" > /dev/null 2>&1; then
  fail "[update-zskills] WI2.1: migrated placeholders still have fill-in instructions" \
    "fill in {{UNIT_TEST_CMD|FULL_TEST_CMD|UI_FILE_PATTERNS|MAIN_REPO_PATH}}"
else
  pass "[update-zskills] WI2.1: no fill-in instructions for migrated placeholders"
fi

# WI 2.2 — Placeholder-mapping table no longer lists the 3 migrated runtime-only
# rows (UNIT_TEST_CMD, FULL_TEST_CMD, UI_FILE_PATTERNS); has the "Runtime-read
# fields" note. Note: MAIN_REPO_PATH was originally migrated out by
# SKILL_FILE_DRIFT_FIX (WI2.2) but Phase 3 of DEFAULT_PORT_CONFIG re-adds it as
# an install-substituted placeholder with dual runtime/install role — see
# SKILL.md's runtime-read prose for the reconciliation. So MAIN_REPO_PATH IS
# expected in the table; only the other three migrated keys must remain absent.
if grep -nE '^\| `\{\{(UNIT_TEST_CMD|FULL_TEST_CMD|UI_FILE_PATTERNS)\}\}`' \
  "$REPO_ROOT/skills/update-zskills/SKILL.md" > /dev/null 2>&1; then
  fail "[update-zskills] WI2.2: placeholder table still contains migrated rows" \
    "table rows for migrated keys"
else
  pass "[update-zskills] WI2.2: placeholder table has no migrated rows"
fi
# Runtime-read note prose was tightened in Phase 3 of DEFAULT_PORT_CONFIG to
# acknowledge MAIN_REPO_PATH and DEFAULT_PORT's dual role. The new prose still
# carries the "NOT install-filled" qualifier (with different surrounding text).
check_fixed update-zskills "WI2.2: runtime-read note" \
  'Runtime-read fields (read by hooks and helper scripts at every invocation, NOT install-filled)'

echo ""
echo "=== Multi-agent adversarial-loop skills — Agent-tool-required preflight (issue #143) ==="
# These five skills internally dispatch reviewer + devil's-advocate + refiner
# sub-agents (or, in research-and-go's case, Skill-load sibling skills that
# do). They MUST run at top level where the `Agent` tool exists. The
# preflight block surfaces the failure mode loudly when one is dispatched as
# a subagent. The structural section heading is the stable anchor: prose
# inside the block can drift, but `## Preflight — top-level dispatch required`
# must be present in every one of these five skills.
check_fixed refine-plan       "preflight: Agent-tool-required heading (issue #143)" \
  '## Preflight — top-level dispatch required'
check_fixed draft-plan        "preflight: Agent-tool-required heading (issue #143)" \
  '## Preflight — top-level dispatch required'
check_fixed draft-tests       "preflight: Agent-tool-required heading (issue #143)" \
  '## Preflight — top-level dispatch required'
check_fixed research-and-plan "preflight: Agent-tool-required heading (issue #143)" \
  '## Preflight — top-level dispatch required'
check_fixed research-and-go   "preflight: Agent-tool-required heading (issue #143)" \
  '## Preflight — top-level dispatch required'

echo ""
echo "=== /draft-tests — behavior contracts (WI 6.3) ==="
# Anchor: tests/test-skill-conformance.sh draft-tests block — one check
# per WI 6.3 sub-bullet of plans/DRAFT_TESTS_SKILL_PLAN.md (current count:
# 11). When WI 6.3 grows or shrinks, add or remove a single check line
# here in tandem; AC-6.2 is a list-membership invariant, not a literal
# count. WI 6.3 is the authoritative enumeration source.
#
# 1. Frontmatter shape (incl. `[guidance...]` positional tail in argument-hint)
check       draft-tests "frontmatter argument-hint with [guidance...]" \
  '^argument-hint:[[:space:]]+"<plan-file> \[rounds N\] \[guidance\.\.\.\]"'
# 2. Tracking marker basename matches canonical scheme `fulfilled.draft-tests.<id>`
check_fixed draft-tests "fulfilled marker basename" \
  'fulfilled.draft-tests.$TRACKING_ID'
# 3. NOT-a-finding list verbatim (distinctive phrase from WI 4.3)
check_fixed draft-tests "NOT-a-finding list (WI 4.3)" \
  'Type-system-enforced preconditions'
# 4. "Zero findings is valid" framing (WI 4.4)
check_fixed draft-tests "zero findings is valid (WI 4.4)" \
  'Zero findings is valid'
# 5. Orchestrator-level coverage-floor pre-check (WI 4.8)
check_fixed draft-tests "orchestrator-level coverage-floor pre-check (WI 4.8)" \
  'orchestrator-level coverage-floor pre-check'
# 6. Convergence is the orchestrator's judgment, not the refiner's self-call (AC-4.9)
check_fixed draft-tests "orchestrator's judgment, not refiner self-call (AC-4.9)" \
  "orchestrator's judgment"
# 7. Broad-form checksum-boundary rule
check_fixed draft-tests "broad-form checksum boundary (WI 1.5)" \
  'next level-2 heading'
# 8. Broad-form backfill-insertion rule
check_fixed draft-tests "broad-form backfill insertion (WI 5.2)" \
  'ANY non-phase'
# 9. Broad-form Test-Spec-Revisions placement rule
check_fixed draft-tests "broad-form Test-Spec-Revisions placement (WI 5.6)" \
  '(other than `## Phase'
# 10. Fenced-code-block-aware boundary scan
check_fixed draft-tests "fenced-code-block-aware boundary scan" \
  'in_code == 0'
# 11. Hardened jq-absence assertion (AC-6.6) — fails closed when SKILL.md
#     is missing; word-boundary regex so `jquery` and `_jq_helper` don't
#     match but real `jq` invocations (`| jq '.'`, `jq -r ...`) do; -I
#     skips binary files. Exact pattern per AC-6.6.
if test -f "$REPO_ROOT/skills/draft-tests/SKILL.md" \
   && ! grep -rIE '(^|[^a-zA-Z_])jq([^a-zA-Z_]|$)' "$REPO_ROOT/skills/draft-tests/" > /dev/null 2>&1; then
  pass "[draft-tests] no \`jq\` standalone-word usage (AC-6.6 hardened pattern)"
else
  if [ ! -f "$REPO_ROOT/skills/draft-tests/SKILL.md" ]; then
    fail "[draft-tests] AC-6.6 jq-absence: skills/draft-tests/SKILL.md missing (fail-closed)" \
      "test -f skills/draft-tests/SKILL.md"
  else
    fail "[draft-tests] AC-6.6 jq-absence: standalone \`jq\` word found in skills/draft-tests/" \
      '(^|[^a-zA-Z_])jq([^a-zA-Z_]|$)'
    grep -rIEn '(^|[^a-zA-Z_])jq([^a-zA-Z_]|$)' "$REPO_ROOT/skills/draft-tests/" >&2
  fi
fi

echo ""
echo "=== /draft-tests — worked example (AC-6.3) ==="
# AC-6.3: tests/fixtures/draft-tests/examples/ exists and contains
# README.md + DRAFT_TESTS_EXAMPLE_PLAN_before.md + DRAFT_TESTS_EXAMPLE_PLAN.md.
# diff between the two plan files shows (i) appended `### Tests` in at
# least one Pending phase and (ii) no changes to Completed-phase
# sections. Negative assertion: no example files under plans/examples/.
EXAMPLES_DIR="$REPO_ROOT/tests/fixtures/draft-tests/examples"
EX_BEFORE="$EXAMPLES_DIR/DRAFT_TESTS_EXAMPLE_PLAN_before.md"
EX_AFTER="$EXAMPLES_DIR/DRAFT_TESTS_EXAMPLE_PLAN.md"
EX_README="$EXAMPLES_DIR/README.md"

if [ -d "$EXAMPLES_DIR" ]; then
  pass "[draft-tests] AC-6.3: examples directory exists at tests/fixtures/draft-tests/examples/"
else
  fail "[draft-tests] AC-6.3: examples directory" "$EXAMPLES_DIR missing"
fi

for f in "$EX_README" "$EX_BEFORE" "$EX_AFTER"; do
  if [ -f "$f" ]; then
    pass "[draft-tests] AC-6.3: $(basename "$f") present"
  else
    fail "[draft-tests] AC-6.3: $(basename "$f") present" "$f missing"
  fi
done

# diff-shape assertions: at least one `### Tests` line appears only in
# the after-file (i.e., is appended), and the Phase 1 (Completed) section
# is byte-identical between before and after.
if [ -f "$EX_BEFORE" ] && [ -f "$EX_AFTER" ]; then
  DIFF_OUT=$(diff "$EX_BEFORE" "$EX_AFTER" || true)
  # (i) appended `### Tests` in at least one Pending phase
  if printf '%s\n' "$DIFF_OUT" | grep -qE '^>[[:space:]]+### Tests'; then
    pass "[draft-tests] AC-6.3 (i): diff shows an appended ### Tests subsection"
  else
    fail "[draft-tests] AC-6.3 (i): diff lacks an appended ### Tests subsection" \
      "no '> ### Tests' in diff"
  fi
  # (ii) no changes to Completed-phase sections — extract Phase 1 region
  # from each file (Phase 1 is the Completed phase per the worked-example
  # spec) and require byte-identical.
  P1_BEFORE=$(awk '/^## Phase 1/,/^## Phase 2/' "$EX_BEFORE")
  P1_AFTER=$(awk '/^## Phase 1/,/^## Phase 2/' "$EX_AFTER")
  if [ "$P1_BEFORE" = "$P1_AFTER" ]; then
    pass "[draft-tests] AC-6.3 (ii): Phase 1 (Completed) section byte-identical"
  else
    fail "[draft-tests] AC-6.3 (ii): Phase 1 (Completed) section drifted" \
      "before-vs-after Phase 1 differs"
  fi
fi

# Negative assertion: no example files under plans/examples/.
if [ ! -e "$REPO_ROOT/plans/examples" ]; then
  pass "[draft-tests] AC-6.3 negative: plans/examples/ absent (examples are under tests/fixtures/, not plans/)"
elif [ -d "$REPO_ROOT/plans/examples" ] \
     && [ -z "$(find "$REPO_ROOT/plans/examples" -maxdepth 1 -type f 2>/dev/null)" ]; then
  pass "[draft-tests] AC-6.3 negative: plans/examples/ contains no files"
else
  fail "[draft-tests] AC-6.3 negative: example files found under plans/examples/" \
    "examples must live under tests/fixtures/draft-tests/examples/"
  ls -la "$REPO_ROOT/plans/examples" >&2 || true
fi

echo ""
echo "=== create-worktree.sh caller contract ==="
# Every multi-line `bash ".../skills/create-worktree/scripts/create-worktree.sh" \` invocation in
# skills/ must include `--pipeline-id` within the next 12 lines. Doc-prose
# mentions (non-backslash-terminated `create-worktree.sh` lines) are not
# invocations and are ignored here.
#
# This catches the Phase 2/3 class of bug: a caller migrates to
# create-worktree.sh but forgets to plumb through its pipeline ID, which
# the runtime would only surface if canaries actually exercise tracking
# enforcement. The conformance test catches it at grep time.
PIPELINE_ID_CONTRACT_FAIL=0
PIPELINE_ID_CONTRACT_CALLS=0
while IFS=: read -r file lineno _; do
  [ -z "$file" ] && continue
  PIPELINE_ID_CONTRACT_CALLS=$((PIPELINE_ID_CONTRACT_CALLS + 1))
  # Look at lines $lineno through $lineno+12 in $file.
  slice=$(sed -n "${lineno},$((lineno + 12))p" "$file" 2>/dev/null)
  if ! echo "$slice" | grep -q -- '--pipeline-id'; then
    fail "create-worktree caller missing --pipeline-id" "$file:$lineno"
    PIPELINE_ID_CONTRACT_FAIL=$((PIPELINE_ID_CONTRACT_FAIL + 1))
  fi
done < <(grep -rn --include='*.md' -E 'scripts/create-worktree\.sh.*\\$' "$REPO_ROOT/skills/")
# Guard against the pattern matching zero lines (which would make the
# "every caller passes" claim vacuously true). We know Phase 3 has 5
# multi-line invocation blocks across skills/run-plan (×2), skills/fix-issues,
# and skills/do/modes (×2). Plus the /create-worktree SKILL.md's own
# documentation example (~1). So ≥6 expected. If the pattern silently
# stopped matching, the test MUST fail rather than quietly pass.
if [ "$PIPELINE_ID_CONTRACT_CALLS" -lt 6 ]; then
  fail "create-worktree caller scan found too few invocations (${PIPELINE_ID_CONTRACT_CALLS} < 6) — pattern broken?" "grep regex drift"
  PIPELINE_ID_CONTRACT_FAIL=$((PIPELINE_ID_CONTRACT_FAIL + 1))
fi
if [ "$PIPELINE_ID_CONTRACT_FAIL" -eq 0 ]; then
  pass "every create-worktree.sh invocation in skills/ passes --pipeline-id (scanned ${PIPELINE_ID_CONTRACT_CALLS})"
fi

# No caller may export or inline-set ZSKILLS_PIPELINE_ID as a side-channel.
# The env var has no effect on the script (--pipeline-id is the only input),
# but setting it near a create-worktree.sh call is a code smell — a relic of
# the Phase-3-era bug where callers leaned on env-var plumbing. Flag any.
if grep -rn --include='*.md' -E 'export[[:space:]]+ZSKILLS_PIPELINE_ID' "$REPO_ROOT/skills/" > /dev/null 2>&1; then
  fail "skills/ contains 'export ZSKILLS_PIPELINE_ID'" "side-channel leak"
  grep -rn --include='*.md' -E 'export[[:space:]]+ZSKILLS_PIPELINE_ID' "$REPO_ROOT/skills/" >&2
else
  pass "no 'export ZSKILLS_PIPELINE_ID' in skills/ (flag is the only interface)"
fi

echo ""
echo "=== No skill-file drift hardcodes ==="
# Deny-list scan for forbidden literals in skills/**/*.md. Single source
# of truth for the literal list lives in tests/fixtures/forbidden-literals.txt
# — the same file that hooks/warn-config-drift.sh reads at runtime.
#
# Detection has TWO modes:
#
#   - EXEC-FENCE: hits inside ``` bash / sh / shell / no-language ``` fences
#     are flagged unless the immediately-preceding prose contains an
#     <!-- allow-hardcoded: <literal> reason: ... --> marker that names
#     the literal. Markers accumulate across consecutive lines; any
#     non-blank, non-marker line resets the accumulated set.
#
#   - PROSE-IMPERATIVE: hits in PROSE outside fences, when the literal
#     appears in a code-span on a bullet (`- `, `* `) or numbered-list
#     (`N. `) line that ALSO contains a sentence-start imperative verb
#     (`Run`, `Execute`, `Invoke` — capitalized; `(^|[.;:][[:space:]]+|\*\*)`
#     prefix). Lower-case `run` does not trigger (avoids past-participle
#     false-positives like "has run" / "can run").
#
# Both modes strip a leading `>` blockquote-prefix before applying their
# regexes — load-bearing for the run-plan worktree-test recipe at
# skills/run-plan/SKILL.md:898-930, where bash fences live inside a
# blockquote.
#
# Fixture format:
#   - One literal per line. Comments (`#`) and blank lines skipped.
#   - Default: fixed-substring match.
#   - `re:` prefix: extended regex (grep -E / `=~`). The pattern is
#     unanchored unless it self-anchors. The allowlist marker for a
#     regex entry names the pattern WITHOUT the `re:` prefix.
#
# When adding a new config field whose value could appear hardcoded in
# skill files, add the antipattern literal to
# tests/fixtures/forbidden-literals.txt. Both the test and
# hooks/warn-config-drift.sh read from this file — no code change.

FORBIDDEN_FIXTURE="$REPO_ROOT/tests/fixtures/forbidden-literals.txt"

if [ ! -r "$FORBIDDEN_FIXTURE" ]; then
  fail "forbidden-literals fixture readable" "$FORBIDDEN_FIXTURE missing or unreadable"
else
  # Read fixture once. Split into FIXED (substring) and REGEX (extended-regex) entries.
  FIXED_LITERALS=()
  REGEX_PATTERNS=()
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    [[ "$entry" =~ ^# ]] && continue
    if [[ "$entry" =~ ^re: ]]; then
      REGEX_PATTERNS+=("${entry#re:}")
    else
      FIXED_LITERALS+=("$entry")
    fi
  done < "$FORBIDDEN_FIXTURE"

  DRIFT_FAIL=0
  DRIFT_HITS=()

  while IFS= read -r skill_file; do
    in_fence=0
    fence_type=""
    unset allowed_in_fence; declare -A allowed_in_fence=()
    prev_lines=()
    line_no=0
    while IFS= read -r line; do
      line_no=$((line_no + 1))
      # Blockquote normalisation: strip a leading `>` + optional space
      # before applying any structural regex. Without this, blockquoted
      # fenced bash blocks (` >    ```bash`) go undetected.
      norm_line="$line"
      if [[ "$norm_line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
        norm_line="${BASH_REMATCH[1]}"
      fi

      if [ "$in_fence" -eq 0 ]; then
        # Outside any fence.
        if [[ "$norm_line" =~ ^[[:space:]]*\<!--[[:space:]]+allow-hardcoded:[[:space:]]+(.+)[[:space:]]+reason:.*--\>[[:space:]]*$ ]]; then
          captured="${BASH_REMATCH[1]}"
          # Trim trailing whitespace.
          captured="${captured%"${captured##*[![:space:]]}"}"
          prev_lines+=("$captured")
        elif [[ "$norm_line" =~ ^[[:space:]]*\`\`\`([a-zA-Z0-9_+-]*)[[:space:]]*$ ]]; then
          # Fence-opener of any kind. Track exec vs other so non-shell
          # fences (json, markdown, etc.) don't get scanned for shell
          # literals — but their bounds are still tracked.
          lang="${BASH_REMATCH[1]}"
          in_fence=1
          if [ -z "$lang" ] || [ "$lang" = "bash" ] || [ "$lang" = "sh" ] || [ "$lang" = "shell" ]; then
            fence_type="exec"
          else
            fence_type="other"
          fi
          allowed_in_fence=()
          if [ "$fence_type" = "exec" ]; then
            for lit in "${prev_lines[@]:-}"; do
              [ -n "$lit" ] && allowed_in_fence["$lit"]=1
            done
          fi
          prev_lines=()
          continue
        else
          # Any other non-blank line resets the marker block.
          [ -n "$norm_line" ] && prev_lines=()
        fi
        # PROSE-IMPERATIVE detection: bullet/numbered line with a
        # code-span AND a sentence-start imperative verb.
        if [[ "$norm_line" =~ ^[[:space:]]*([-*]|[0-9]+\.) ]] \
           && [[ "$norm_line" =~ \`[^\`]+\` ]] \
           && [[ "$norm_line" =~ (^|[.\;\:][[:space:]]+|\*\*)(Run|Execute|Invoke)[[:space:]] ]]; then
          for literal in "${FIXED_LITERALS[@]}"; do
            if [[ "$norm_line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
              DRIFT_HITS+=("DRIFT (prose-imperative): $skill_file:$line_no contains '$literal'. Replace with \$VAR (preferred) or add an allow-hardcoded marker if legitimately required.")
              DRIFT_FAIL=1
            fi
          done
          for pattern in "${REGEX_PATTERNS[@]}"; do
            if [[ "$norm_line" =~ $pattern ]] && [ -z "${allowed_in_fence[$pattern]:-}" ]; then
              DRIFT_HITS+=("DRIFT (prose-imperative): $skill_file:$line_no matches forbidden regex '$pattern'. Replace with \$VAR (preferred) or add an allow-hardcoded marker if legitimately required.")
              DRIFT_FAIL=1
            fi
          done
        fi
        continue
      fi

      # Inside a fence.
      if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
        in_fence=0
        fence_type=""
        allowed_in_fence=()
        prev_lines=()
        continue
      fi
      # Only scan exec-type fences (bash / sh / shell / no-language).
      if [ "$fence_type" != "exec" ]; then
        continue
      fi
      for literal in "${FIXED_LITERALS[@]}"; do
        if [[ "$norm_line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
          DRIFT_HITS+=("DRIFT: $skill_file:$line_no contains '$literal' inside a bash fence without an allow-hardcoded marker. Replace with \$VAR (preferred) or add the marker if legitimately required.")
          DRIFT_FAIL=1
        fi
      done
      for pattern in "${REGEX_PATTERNS[@]}"; do
        if [[ "$norm_line" =~ $pattern ]] && [ -z "${allowed_in_fence[$pattern]:-}" ]; then
          DRIFT_HITS+=("DRIFT: $skill_file:$line_no matches forbidden regex '$pattern' inside a bash fence without an allow-hardcoded marker. Replace with \$VAR (preferred) or add the marker if legitimately required.")
          DRIFT_FAIL=1
        fi
      done
    done < "$skill_file"
  done < <(find "$REPO_ROOT/skills" -name '*.md' | sort)

  if [ "$DRIFT_FAIL" -eq 0 ]; then
    pass "no skill-file drift hardcodes (deny-list clean against tests/fixtures/forbidden-literals.txt)"
  else
    fail "skill-file drift hardcodes detected" "${#DRIFT_HITS[@]} hit(s)"
    for h in "${DRIFT_HITS[@]}"; do
      printf '    %s\n' "$h" >&2
    done
  fi
fi

echo ""
echo "=== Worktree-test blockquote structural AC ==="
# WI 4.6 — Phase 2 WI 2.2 migrated the worktree-test recipe blockquote at
# skills/run-plan/SKILL.md:898-930 from raw `npm start` / `npm run test:all` /
# `.test-results.txt` literals to `$DEV_SERVER_CMD` / `$FULL_TEST_CMD` /
# `$TEST_OUTPUT_FILE`. This AC mechanizes the structural invariant so a
# future agent can't silently revert one of the substitutions and have
# only the deny-list catch it (or worse, slip past as a non-fence literal).
BQ_TMP=$(mktemp)
awk '/^[[:space:]]*> \*\*Worktree test recipe:\*\*/,/^[[:space:]]*8\. \*\*No steps skipped/' \
    "$REPO_ROOT/skills/run-plan/SKILL.md" > "$BQ_TMP"

if [ ! -s "$BQ_TMP" ]; then
  fail "worktree-test blockquote: extracted bounds non-empty" "awk produced 0 lines — anchors drifted?"
elif grep -qE 'npm start|npm run test:all|\.test-results\.txt' "$BQ_TMP"; then
  fail "worktree-test blockquote: no raw literal" "raw literal in $BQ_TMP — see $REPO_ROOT/skills/run-plan/SKILL.md:898-930"
  grep -nE 'npm start|npm run test:all|\.test-results\.txt' "$BQ_TMP" >&2
elif ! grep -qE '\$DEV_SERVER_CMD' "$BQ_TMP"; then
  fail "worktree-test blockquote: \$DEV_SERVER_CMD present" "missing in $BQ_TMP"
elif ! grep -qE '\$TEST_OUTPUT_FILE' "$BQ_TMP"; then
  fail "worktree-test blockquote: \$TEST_OUTPUT_FILE present" "missing in $BQ_TMP"
elif ! grep -qE '\$FULL_TEST_CMD' "$BQ_TMP"; then
  fail "worktree-test blockquote: \$FULL_TEST_CMD present" "missing in $BQ_TMP"
else
  pass "worktree-test blockquote: \$DEV_SERVER_CMD / \$FULL_TEST_CMD / \$TEST_OUTPUT_FILE all present, no raw literals"
fi
rm -f "$BQ_TMP"

# Substitution-discipline rule at SKILL.md:179-187 must enumerate all 3 vars.
DISCIPLINE_BLOCK=$(sed -n '179,187p' "$REPO_ROOT/skills/run-plan/SKILL.md")
if echo "$DISCIPLINE_BLOCK" | grep -q '\$DEV_SERVER_CMD' \
   && echo "$DISCIPLINE_BLOCK" | grep -q '\$FULL_TEST_CMD' \
   && echo "$DISCIPLINE_BLOCK" | grep -q '\$TEST_OUTPUT_FILE'; then
  pass "substitution-discipline at SKILL.md:179-187 names all 3 vars"
else
  fail "substitution-discipline at SKILL.md:179-187 names all 3 vars" "block: $DISCIPLINE_BLOCK"
fi

echo ""
echo "=== Positive-side fence-local drift check (WI 5.2) ==="
# Two-sided drift-regression test (refine-2 DA2.14/DA2.17). The negative
# side above catches re-hardcoded literals. This positive side catches the
# inverse regression mode: a fence references one of the 6 config-derived
# vars but the canonical helper-source preamble (zskills-resolve-config.sh)
# is missing from that fence — so the var resolves to empty at runtime.
#
# Fence-local: per-fence accumulators reset on fence-open. PROSE references
# to vars OUTSIDE fences (e.g., the substitution-discipline annotation at
# run-plan/SKILL.md:181) are NOT consumers — they are explanation — and
# the fence-local check correctly ignores them.
#
# Var list (matches Phase 1 helper's resolved set):
#   UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, DEV_SERVER_CMD,
#   TEST_OUTPUT_FILE, COMMIT_CO_AUTHOR
POS_DRIFT_FAIL=0
POS_DRIFT_HITS=()
POS_VAR_RE='\$\{?(UNIT_TEST_CMD|FULL_TEST_CMD|TIMEZONE|DEV_SERVER_CMD|TEST_OUTPUT_FILE|COMMIT_CO_AUTHOR)\}?'

scan_positive_side() {
  local target_root="$1"
  local fail_var_name="$2"
  local hits_var_name="$3"
  local local_fail=0
  local -a local_hits=()
  while IFS= read -r skill_file; do
    in_fence=0
    fence_type=""
    fence_uses_var=0
    fence_has_preamble=0
    fence_is_blockquoted=0
    fence_self_resolves=0
    fence_open_line=0
    line_no=0
    prev_line=""
    while IFS= read -r line; do
      line_no=$((line_no + 1))
      # Detect blockquote prefix (load-bearing: blockquote-fenced fences
      # are governed by the substitution-discipline annotation, not the
      # helper-source preamble — see skills/run-plan/SKILL.md:179-187).
      raw_is_bq=0
      norm_line="$line"
      if [[ "$norm_line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
        norm_line="${BASH_REMATCH[1]}"
        raw_is_bq=1
      fi
      if [ "$in_fence" -eq 0 ]; then
        if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`([a-zA-Z0-9_+-]*)[[:space:]]*$ ]]; then
          lang="${BASH_REMATCH[1]}"
          in_fence=1
          if [ -z "$lang" ] || [ "$lang" = "bash" ] || [ "$lang" = "sh" ] || [ "$lang" = "shell" ]; then
            fence_type="exec"
          else
            fence_type="other"
          fi
          fence_uses_var=0
          fence_has_preamble=0
          fence_self_resolves=0
          fence_is_blockquoted=$raw_is_bq
          fence_open_line=$line_no
          # The preamble may live on the line immediately above the
          # fence-opener (i.e., the prose `. "$CLAUDE_PROJECT_DIR/.../zskills-resolve-config.sh"`
          # source-line pattern is sometimes itself outside the fence).
          # Check prev_line.
          if [[ "$prev_line" == *"zskills-resolve-config.sh"* ]]; then
            fence_has_preamble=1
          fi
        fi
        prev_line="$norm_line"
        continue
      fi
      # Inside a fence.
      if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
        # Fence-close: evaluate. Three legitimate equivalents to the
        # helper-source preamble:
        #   (1) helper-source: `. "$CLAUDE_PROJECT_DIR/.../zskills-resolve-config.sh"`
        #   (2) inline self-resolution: a fence that DEFINES the var by
        #       reading config inline (CONFIG_CONTENT=$(cat ...) +
        #       BASH_REMATCH extraction) — circular to require helper-source.
        #   (3) blockquote-fenced: governed by the substitution-discipline
        #       at skills/run-plan/SKILL.md:179-187 (model substitutes
        #       resolved literals before emission), not by helper-source.
        if [ "$fence_type" = "exec" ] \
           && [ "$fence_uses_var" -eq 1 ] \
           && [ "$fence_has_preamble" -eq 0 ] \
           && [ "$fence_self_resolves" -eq 0 ] \
           && [ "$fence_is_blockquoted" -eq 0 ]; then
          local_hits+=("DRIFT (positive-side): $skill_file:$fence_open_line bash fence references one of {UNIT_TEST_CMD,FULL_TEST_CMD,TIMEZONE,DEV_SERVER_CMD,TEST_OUTPUT_FILE,COMMIT_CO_AUTHOR} but does not source zskills-resolve-config.sh in or immediately above the fence (and is neither a self-resolving CONFIG_CONTENT fence nor a blockquoted substitution-discipline fence). Add the helper-source preamble.")
          local_fail=1
        fi
        in_fence=0
        fence_type=""
        fence_uses_var=0
        fence_has_preamble=0
        fence_self_resolves=0
        fence_is_blockquoted=0
        prev_line=""
        continue
      fi
      if [ "$fence_type" = "exec" ]; then
        if [[ "$norm_line" =~ $POS_VAR_RE ]]; then
          fence_uses_var=1
        fi
        if [[ "$norm_line" == *"zskills-resolve-config.sh"* ]]; then
          fence_has_preamble=1
        fi
        # Inline self-resolution pattern: CONFIG_CONTENT=$(cat ...) +
        # BASH_REMATCH extraction. The fence is itself the resolver.
        if [[ "$norm_line" =~ CONFIG_CONTENT=\$\(cat ]] \
           || [[ "$norm_line" =~ \[\[[[:space:]]*\"\$\(cat ]]; then
          fence_self_resolves=1
        fi
      fi
    done < "$skill_file"
  done < <(find "$target_root" -name '*.md' | sort)
  # Export results via name-refs.
  printf -v "$fail_var_name" '%s' "$local_fail"
  if [ "$local_fail" -eq 1 ]; then
    # Stash hits into a global by appending to the named array.
    for h in "${local_hits[@]}"; do
      eval "$hits_var_name+=(\"\$h\")"
    done
  fi
}

# Smoke fixtures (refine-2 DA2.14): 2 synthetic positive-side cases + 1
# real-tree case. Use a temp dir so we exercise the same scan_positive_side
# logic on small fixtures with known ground truth.
POS_FIXTURE_DIR=$(mktemp -d)
mkdir -p "$POS_FIXTURE_DIR/skills/syn-pass" "$POS_FIXTURE_DIR/skills/syn-fail"
cat > "$POS_FIXTURE_DIR/skills/syn-pass/SKILL.md" <<'PASS_FIXTURE'
# syn-pass

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
echo "$FULL_TEST_CMD"
```
PASS_FIXTURE
cat > "$POS_FIXTURE_DIR/skills/syn-fail/SKILL.md" <<'FAIL_FIXTURE'
# syn-fail

```bash
echo "$FULL_TEST_CMD"
echo "no preamble — should fail positive-side"
```
FAIL_FIXTURE

# Synthetic-PASS case: scan only syn-pass; expect 0 hits.
SYN_PASS_FAIL=0
SYN_PASS_HITS=()
scan_positive_side "$POS_FIXTURE_DIR/skills/syn-pass" SYN_PASS_FAIL SYN_PASS_HITS
if [ "$SYN_PASS_FAIL" -eq 0 ]; then
  pass "positive-side synthetic-PASS: fence using \$FULL_TEST_CMD WITH preamble accepted"
else
  fail "positive-side synthetic-PASS: should accept fence with preamble" "${SYN_PASS_HITS[*]:-no hits}"
fi

# Synthetic-FAIL case: scan only syn-fail; expect 1 hit.
SYN_FAIL_FAIL=0
SYN_FAIL_HITS=()
scan_positive_side "$POS_FIXTURE_DIR/skills/syn-fail" SYN_FAIL_FAIL SYN_FAIL_HITS
if [ "$SYN_FAIL_FAIL" -eq 1 ] && [ "${#SYN_FAIL_HITS[@]}" -ge 1 ]; then
  pass "positive-side synthetic-FAIL: fence using \$FULL_TEST_CMD WITHOUT preamble flagged"
else
  fail "positive-side synthetic-FAIL: should flag fence missing preamble" "fail=$SYN_FAIL_FAIL, hits=${#SYN_FAIL_HITS[@]}"
fi

rm -rf "$POS_FIXTURE_DIR"

# Real-tree case: scan current skills/ — expect 0 drift after Phase 2 migration.
REAL_POS_FAIL=0
REAL_POS_HITS=()
scan_positive_side "$REPO_ROOT/skills" REAL_POS_FAIL REAL_POS_HITS
if [ "$REAL_POS_FAIL" -eq 0 ]; then
  pass "positive-side real-tree: every fence using a config-var also sources zskills-resolve-config.sh"
else
  fail "positive-side real-tree: ${#REAL_POS_HITS[@]} fence(s) reference config-vars without preamble" "see hits below"
  for h in "${REAL_POS_HITS[@]}"; do
    printf '    %s\n' "$h" >&2
  done
fi

# Skill-dir cleanliness: no dotfiles or build artifacts in GIT-TRACKED content.
# Scoped to `git ls-files <skill-dir>` rather than `find` so that working-tree
# runtime artifacts (briefing.py's __pycache__, zskills_monitor's __pycache__,
# editor swap files, etc.) do NOT trip the gate. The cleanliness rule enforces
# what consumers see — i.e., what's tracked in git — not what lives transiently
# in a developer's working tree. (refine-plan F-DA-4 / F-DA-14: the prior
# `find`-based form would hard-fail on day-zero migration because briefing and
# zskills-dashboard both materialize __pycache__ when their Python runs, and
# `.gitkeep` is intentionally tracked in zskills-dashboard's static dir.)
#
# `.gitkeep` is the universal Unix idiom for tracking an otherwise-empty
# directory; allow-list it explicitly. Other dotfiles in tracked content
# (e.g., `.env`, `.DS_Store`, `.swp`) remain rejected.
echo "=== Skill-dir cleanliness ==="
for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  skill_rel="${skill_dir#$REPO_ROOT/}"
  skill_rel="${skill_rel%/}"
  tracked=$(git -C "$REPO_ROOT" ls-files -- "$skill_rel")
  # Reject any tracked dotfile EXCEPT `.gitkeep` (allow-listed).
  dotfile_hits=$(printf '%s\n' "$tracked" | awk -F/ '
    { name=$NF }
    name ~ /^\./ && name != ".gitkeep" { print }
  ')
  # __pycache__ / node_modules: should never be tracked. If git ls-files
  # reports any, that IS a real cleanliness regression.
  # grep returns 1 when no matches; that's the success case here. Use a
  # conditional rather than `|| true` so a real grep error (regex syntax,
  # broken pipe) still surfaces.
  artifact_hits=$(printf '%s\n' "$tracked" | grep -E '(^|/)(__pycache__|node_modules)(/|$)') || \
    [ "$?" -eq 1 ] || { echo "FAIL: grep error" >&2; exit 1; }
  if [ -n "$dotfile_hits" ] || [ -n "$artifact_hits" ]; then
    fail "skill $name: contains tracked dotfile/artifact (skill dirs must be clean)" \
      "$(printf '%s\n%s\n' "$dotfile_hits" "$artifact_hits")"
    continue
  fi
  pass "skill $name: clean (no tracked dotfiles/artifacts)"
done

echo ""
echo "=== Per-skill version frontmatter ==="
for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/; do
  skill_md="${skill_dir}SKILL.md"
  [ -f "$skill_md" ] || continue
  name=$(basename "$skill_dir")
  version=$(bash "$REPO_ROOT/scripts/frontmatter-get.sh" "$skill_md" metadata.version) || {
    fail "skill $name: metadata.version missing or unreadable" "from $skill_md"
    continue
  }
  if [[ ! "$version" =~ ^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$ ]]; then
    fail "skill $name: metadata.version '$version' does not match YYYY.MM.DD+HHHHHH (validated month/day ranges)" "from $skill_md"
    continue
  fi
  # Stale-hash check.
  stored_hash="${version##*+}"
  fresh_hash=$(bash "$REPO_ROOT/scripts/skill-content-hash.sh" "$skill_dir")
  if [ "$stored_hash" != "$fresh_hash" ]; then
    fail "skill $name: stored hash $stored_hash != fresh hash $fresh_hash" "version line stale"
    continue
  fi
  pass "skill $name: metadata.version=$version"
done

# Mirror desync check (Round-2 F-R2-7) + allow-list for source-less mirrors
# (Round-3 F-DA-R3-3). The allow-list is hardcoded; new entries require a
# documented justification per §1.6.
#
#   playwright-cli — pre-dates the source/mirror split; vendor-bundled.
#   social-seo     — pre-dates the source/mirror split; vendor-bundled.
#
# Any other source-less mirror is a CI failure (orphaned cleanup signal).
MIRROR_ONLY_OK="playwright-cli social-seo"
echo ""
echo "=== Per-skill version mirror parity ==="
for mirror_dir in "$REPO_ROOT/.claude/skills"/*/; do
  mirror_md="${mirror_dir}SKILL.md"
  [ -f "$mirror_md" ] || continue
  name=$(basename "$mirror_dir")
  src_dir="$REPO_ROOT/skills/$name"
  if [ ! -f "$src_dir/SKILL.md" ]; then
    # No source — must be on the allow-list.
    if [[ " $MIRROR_ONLY_OK " == *" $name "* ]]; then
      pass "skill $name: mirror-only (allow-listed, skipped)"
      continue
    fi
    fail "mirrored skill $name: no source counterpart and not on MIRROR_ONLY_OK allow-list" \
      "orphaned mirror — delete .claude/skills/$name or add a source dir"
    continue
  fi
  mirror_ver=$(bash "$REPO_ROOT/scripts/frontmatter-get.sh" "$mirror_md" metadata.version) || {
    fail "mirrored skill $name: metadata.version missing or unreadable" "from $mirror_md"
    continue
  }
  mirror_hash="${mirror_ver##*+}"
  src_fresh_hash=$(bash "$REPO_ROOT/scripts/skill-content-hash.sh" "$src_dir")
  if [ "$mirror_hash" != "$src_fresh_hash" ]; then
    fail "mirrored skill $name: stored hash $mirror_hash != source projection $src_fresh_hash" "mirror desync"
    continue
  fi
  pass "mirrored skill $name: hash matches source projection"
done

echo ""
echo "=== PROSE-IMPERATIVE substitution-discipline coverage (WI 5.7) ==="
# refine-2 R2.12 follow-on. For each PROSE-migrated $VAR reference
# (8 npm-run-test:all + 1 npm-start sites — see plan WI 5.7), assert that
# within 5 lines (forward or backward) of the migrated $VAR reference
# there is EITHER (a) an inline annotation referencing
# zskills-resolve-config.sh, OR (b) a pointer to a per-skill canonical-
# prelude config-read block (existing `CONFIG_CONTENT=$(cat ...)` pattern).
#
# Annotation form (Phase 2 added these inline alongside the migration):
#
#     run `$FULL_TEST_CMD` (resolve via
#       `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
#       if you don't already have it in your environment) before committing.
#
# This test re-derives the migrated-site set at execution time (line
# numbers drift across edits) so it stays robust as files change.
#
# Detection: outside any bash fence, a bullet/numbered-list line
# containing a code-span with $FULL_TEST_CMD or $DEV_SERVER_CMD. Note:
# the deny-list detector's tighter PROSE-IMPERATIVE form requires a
# sentence-start imperative verb (`Run`/`Execute`/`Invoke`) to avoid
# false-positives on bare literals; the COVERAGE check here is broader
# because the migration introduced annotation-bearing prose forms that
# don't always carry an imperative verb (e.g., `- \`$FULL_TEST_CMD\` (resolve via ...)`).
PROSE_VAR_RE='\$\{?(FULL_TEST_CMD|DEV_SERVER_CMD)\}?'
COVERAGE_FAIL=0
COVERAGE_SITES_SCANNED=0
declare -a COVERAGE_HITS=()

while IFS= read -r skill_file; do
  in_fence=0
  line_no=0
  # Read whole file into array for ±5 windowing.
  mapfile -t FILE_LINES < "$skill_file"
  # Track fence state independently while iterating with index.
  total=${#FILE_LINES[@]}
  for (( idx=0; idx<total; idx++ )); do
    line="${FILE_LINES[$idx]}"
    raw_is_bq=0
    norm_line="$line"
    if [[ "$norm_line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
      norm_line="${BASH_REMATCH[1]}"
      raw_is_bq=1
    fi
    if [ "$in_fence" -eq 0 ]; then
      if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`([a-zA-Z0-9_+-]*)[[:space:]]*$ ]]; then
        in_fence=1
        continue
      fi
      # Skip blockquoted prose: substitution discipline governs (see
      # skills/run-plan/SKILL.md:179-187 — model substitutes resolved
      # literals before emitting blockquoted recipes to subagents).
      if [ "$raw_is_bq" -eq 1 ]; then
        continue
      fi
      # Bullet/numbered list with code-span containing one of the migrated
      # $VAR refs. (No imperative-verb gate — see comment block above.)
      if [[ "$norm_line" =~ ^[[:space:]]*([-*]|[0-9]+\.) ]] \
         && [[ "$norm_line" =~ \`[^\`]+\` ]] \
         && [[ "$norm_line" =~ $PROSE_VAR_RE ]]; then
        # Found a PROSE-IMPERATIVE $VAR site. Window ±5 lines.
        win_start=$((idx - 5))
        win_end=$((idx + 5))
        [ "$win_start" -lt 0 ] && win_start=0
        [ "$win_end" -ge "$total" ] && win_end=$((total - 1))
        found=0
        for (( j=win_start; j<=win_end; j++ )); do
          wline="${FILE_LINES[$j]}"
          # (a) inline annotation referencing zskills-resolve-config.sh
          # (b) pointer to per-skill config-read CONFIG_CONTENT=$(cat ...) pattern
          # (c) inline pointer-prose to a resolution section: `(resolved from
          #     config — see X)` / `(resolve via X)` — the migration introduced
          #     these in lieu of inline helper-source where the surrounding
          #     fence already had a resolver.
          if [[ "$wline" == *"zskills-resolve-config.sh"* ]] \
             || [[ "$wline" =~ CONFIG_CONTENT=\$\(cat ]] \
             || [[ "$wline" =~ \(resolved\ from\ config ]] \
             || [[ "$wline" =~ \(resolve\ via ]]; then
            found=1
            break
          fi
        done
        site_lineno=$((idx + 1))
        COVERAGE_SITES_SCANNED=$((COVERAGE_SITES_SCANNED + 1))
        if [ "$found" -eq 0 ]; then
          # Extract var name for message clarity.
          var_match=""
          [[ "$norm_line" =~ $PROSE_VAR_RE ]] && var_match="${BASH_REMATCH[1]}"
          COVERAGE_HITS+=("FAIL: PROSE-IMPERATIVE site at $skill_file:$site_lineno uses \$$var_match without nearby resolution-discipline annotation. Add an inline \`(resolve via ...)\` or pointer to the skill's config-read block.")
          COVERAGE_FAIL=1
        fi
      fi
    else
      if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
        in_fence=0
      fi
    fi
  done
done < <(find "$REPO_ROOT/skills" -name '*.md' | sort)

# Guard against vacuous pass: if zero sites were detected, the regex broke.
# Plan enumerates 9 PROSE-IMPERATIVE sites (8 test-cmd + 1 dev-server).
# Allow some slack (≥7) for natural drift, but flag if obviously broken.
if [ "$COVERAGE_SITES_SCANNED" -lt 7 ]; then
  fail "PROSE-IMPERATIVE coverage: scanned only $COVERAGE_SITES_SCANNED sites (<7) — detector regex broken?" "expected ≥7 from plan enumeration"
elif [ "$COVERAGE_FAIL" -eq 0 ]; then
  pass "PROSE-IMPERATIVE coverage: all $COVERAGE_SITES_SCANNED sites have nearby resolution-discipline annotation"
else
  fail "PROSE-IMPERATIVE coverage: ${#COVERAGE_HITS[@]} of $COVERAGE_SITES_SCANNED sites missing annotation" "see hits below"
  for h in "${COVERAGE_HITS[@]}"; do
    printf '    %s\n' "$h" >&2
  done
fi

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
