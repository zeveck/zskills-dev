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
check_fixed run-plan "compute-cron-fire invocation" 'bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/compute-cron-fire.sh"'
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
check_fixed run-plan "create-worktree invocation" 'bash "$MAIN_ROOT/scripts/create-worktree.sh"'
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
check       commit "--watch unreliable"       '--watch.*(exit code is unreliable|UNRELIABLE)'
check_fixed commit "write-landed"             'bash scripts/write-landed.sh'
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
check_fixed do "sanitize-pipeline-id"         'bash scripts/sanitize-pipeline-id.sh'
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
check       fix-issues "auto-gating prose"          'Auto-flag gating depends on landing mode|gated on \$AUTO'
check_fixed fix-issues "pr ci+fix-cycle always run" 'CI polling, and the fix cycle ALL run regardless of'
check_fixed fix-issues "only merge gated on auto"   'Only `gh pr merge --auto --squash` is gated on `auto`'
check_fixed fix-issues "cherry-pick defers to fix-report" 'Cherry-picks land via `/fix-report`'
check       fix-issues "direct requires auto"       'never run that without|explicit `auto` consent'
check_fixed fix-issues "auto-merge AUTO guard"      'if [ "$AUTO" = "true" ]; then'
check       fix-issues "ci poll always runs in pr.md" 'CI poll \+ fix cycle: ALWAYS|always runs.*interactive and auto'

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

# WI 2.2 — Placeholder-mapping table no longer lists the 4 migrated rows;
# has the "Runtime-read fields" note.
if grep -nE '^\| `\{\{(UNIT_TEST_CMD|FULL_TEST_CMD|UI_FILE_PATTERNS|MAIN_REPO_PATH)\}\}`' \
  "$REPO_ROOT/skills/update-zskills/SKILL.md" > /dev/null 2>&1; then
  fail "[update-zskills] WI2.2: placeholder table still contains migrated rows" \
    "table rows for migrated keys"
else
  pass "[update-zskills] WI2.2: placeholder table has no migrated rows"
fi
check_fixed update-zskills "WI2.2: runtime-read note" \
  'Runtime-read fields (not install-filled)'

echo ""
echo "=== create-worktree.sh caller contract ==="
# Every multi-line `bash ".../scripts/create-worktree.sh" \` invocation in
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
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $FAIL_COUNT -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
