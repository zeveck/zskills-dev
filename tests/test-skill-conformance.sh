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
#
# Slug form (uniform across all 7 helpers): bare `<name>` reroots to
# `$REPO_ROOT/skills/<name>/`; a slug containing `/` (e.g.
# `block-diagram/add-block`) reroots to `$REPO_ROOT/<slug>/` so callers
# can target the block-diagram/ subtree (and future subtrees) without
# helper churn.
check() {
  local skill="$1" label="$2" pattern="$3"
  local skill_dir
  if [[ "$skill" == */* ]]; then
    skill_dir="$REPO_ROOT/$skill"
  else
    skill_dir="$REPO_ROOT/skills/$skill"
  fi
  if grep -rE -e "$pattern" "$skill_dir/" > /dev/null 2>&1; then
    pass "[$skill] $label"
  else
    fail "[$skill] $label" "$pattern"
  fi
}

# check_fixed <skill> <label> <literal>
# Like `check` but uses fixed-string (-F) matching for literals with regex metachars.
check_fixed() {
  local skill="$1" label="$2" pattern="$3"
  local skill_dir
  if [[ "$skill" == */* ]]; then
    skill_dir="$REPO_ROOT/$skill"
  else
    skill_dir="$REPO_ROOT/skills/$skill"
  fi
  if grep -rF -e "$pattern" "$skill_dir/" > /dev/null 2>&1; then
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
  local skill_dir
  if [[ "$skill" == */* ]]; then
    skill_dir="$REPO_ROOT/$skill"
  else
    skill_dir="$REPO_ROOT/skills/$skill"
  fi
  if grep -rE -e "$pattern" "$skill_dir/" > /dev/null 2>&1; then
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
  local target
  if [[ "$skill" == */* ]]; then
    target="$REPO_ROOT/$skill/$relpath"
  else
    target="$REPO_ROOT/skills/$skill/$relpath"
  fi
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

# check_in_file_near <skill> <relative-path> <label> <pattern> <context-pattern> [window-lines]
# Like check_in_file, but requires <pattern> AND <context-pattern> to
# appear within <window-lines> of each other (default 10; pass 0 for
# "same line"). Used for impl-dispatch pin checks (issue #517): the
# literal `subagent_type: "implementer"` must appear ON THE SAME LINE
# as the `Agent` keyword (i.e. on the actual dispatch directive line),
# not in an unrelated comment or footnote. Whole-file `grep -E` would
# let a demoted dispatch site (e.g. subagent_type: "general-purpose")
# pass as long as ANY mention of the pin literal survives elsewhere —
# a comment like `<!-- TODO: re-pin subagent_type: "implementer" -->`
# would satisfy the assertion.
check_in_file_near() {
  local skill="$1" relpath="$2" label="$3" pattern="$4" ctx="$5" window="${6:-10}"
  local target
  if [[ "$skill" == */* ]]; then
    target="$REPO_ROOT/$skill/$relpath"
  else
    target="$REPO_ROOT/skills/$skill/$relpath"
  fi
  if [ ! -f "$target" ]; then
    fail "[$skill/$relpath] $label" "file does not exist"
    return
  fi
  # awk: track the last line numbers at which $pattern and $ctx each
  # matched; pass if they are ever within $window lines of each other.
  if awk -v pat="$pattern" -v ctx="$ctx" -v win="$window" '
    {
      if (index($0, pat))  pat_lines[++pn] = NR
      if (index($0, ctx))  ctx_lines[++cn] = NR
    }
    END {
      for (i = 1; i <= pn; i++) {
        for (j = 1; j <= cn; j++) {
          d = pat_lines[i] - ctx_lines[j]
          if (d < 0) d = -d
          if (d <= win) exit 0
        }
      }
      exit 1
    }
  ' "$target"; then
    pass "[$skill/$relpath] $label"
  else
    fail "[$skill/$relpath] $label" "no '$pattern' within $window lines of '$ctx'"
  fi
}

# check_not_in_file <skill> <relative-path> <label> <pattern>
# Inverted check_in_file.
check_not_in_file() {
  local skill="$1" relpath="$2" label="$3" pattern="$4"
  local target
  if [[ "$skill" == */* ]]; then
    target="$REPO_ROOT/$skill/$relpath"
  else
    target="$REPO_ROOT/skills/$skill/$relpath"
  fi
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
  local target
  if [[ "$skill" == */* ]]; then
    target="$REPO_ROOT/$skill/$relpath"
  else
    target="$REPO_ROOT/skills/$skill/$relpath"
  fi
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
  local target
  if [[ "$skill" == */* ]]; then
    target="$REPO_ROOT/$skill/$relpath"
  else
    target="$REPO_ROOT/skills/$skill/$relpath"
  fi
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

# Phase 4 W4.2(b) (D8): cross-test materialiser-presence check at top.
# The conformance suite is the broadest structural safety net, so before
# the per-skill grep checks run, fail fast if any Phase-2 SessionStart
# materialiser artifact or plugin-lane manifest has gone missing. The
# behavioral correctness of each is exercised by its dedicated test
# (test-sessionstart-materialise.sh, test-plugin-manifest.sh, etc.); this
# is purely a presence/non-deletion tripwire that surfaces a vanished
# artifact here even if a dedicated test were ever (accidentally) dropped.
echo "=== plugin-lane + SessionStart materialiser artifacts — presence (W4.2(b)/D8) ==="
for _art in \
  hooks/session-start-materialise.sh \
  hooks/hooks.json \
  hooks/_lib/plugin-hook-skip-if-mirrored.sh \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  block-diagram/.claude-plugin/plugin.json; do
  if [ -f "$REPO_ROOT/$_art" ]; then
    pass "[materialiser-presence] $_art exists"
  else
    fail "[materialiser-presence] $_art exists" "$_art"
  fi
done

echo "=== /run-plan — behavior contracts ==="
check       run-plan "stop-precedence"              'Takes precedence'
check_fixed run-plan "landing-default"              'LANDING_MODE="cherry-pick"'
check_fixed run-plan "finish-mode resolution"       'FINISH_MODE="finish-auto"'
check_fixed run-plan "finish-mode default empty"    'FINISH_MODE=""'
check       run-plan "direct+main_protected guard"  'direct mode is incompatible with main_protected'
check_fixed run-plan "cherry-pick create-worktree"  '--prefix cp'
check_fixed run-plan "cp worktree slug (single-phase)" '"${PLAN_SLUG}-phase-${PHASE}"'
check_fixed run-plan "cp worktree slug (finish-mode)"  '"${PLAN_SLUG}"'
check_fixed run-plan "pr worktree path"             'WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-'
check_fixed run-plan "pipeline-id echo"             'ZSKILLS_PIPELINE_ID=run-plan.'
check_fixed run-plan ".zskills-tracked write"       '.zskills-tracked'
check_fixed run-plan "test-out per-worktree"        'TEST_OUT="/tmp/zskills-tests/'
check       run-plan "test capture redirect"        '\$TEST_OUT/(\$TEST_OUTPUT_FILE|\$\{TEST_OUTPUT_FILE:-\.test-results\.txt\})" 2>&1'
check_fixed run-plan "compute-cron-fire invocation" 'bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/compute-cron-fire.sh"'
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
check_fixed run-plan "write-landed invocation"      'bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/write-landed.sh"'
check_fixed run-plan "pr-mode bookkeeping"          'PR-mode bookkeeping'
check_fixed run-plan "post-run-invariants"          'bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/post-run-invariants.sh"'
check_fixed run-plan "final-verify marker glob"     'requires.verify-changes.final.'
# PR-mode read-authority (the bug caught during CANARY10 re-run): when
# LANDING_MODE=pr and a feature-branch worktree exists, plan reads MUST
# come from the worktree — main's copy is stale until squash-merge. Step 0
# and Parse Plan read from $PLAN_FILE_FOR_READ, not raw $PLAN_FILE.
check_fixed run-plan "read-auth: PR worktree path"  'PR_WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"'
check_fixed run-plan "read-auth: feature-branch branch" 'PLAN_FILE_FOR_READ="$PR_WORKTREE_PATH/$PLAN_FILE"'
check_fixed run-plan "read-auth: main fallback"     'PLAN_FILE_FOR_READ="$MAIN_ROOT/$PLAN_FILE"'
# PR-body progress sync (issue #60, helper-extraction issue #212): PR mode
# opens the PR once in Phase 6 and used to never revisit the body, leaving
# the progress checklist frozen at Phase 1. The fix wraps the PR body's
# progress section in HTML-comment markers at open time (modes/pr.md) and
# Phase 4 step 5 invokes `scripts/sync-pr-body-progress.sh` to splice an
# updated progress block between the markers. Conformance assertions:
#   1. Both markers exist somewhere under the skill tree (modes/pr.md
#      writes them at PR-open; the helper greps for them at splice time).
#   2. Phase 4 step 5 references the helper script by name (collapsed-prose
#      check — if the orchestrator silently drops the invocation, this
#      tripwires).
#   3. The helper exists and is executable.
#   4. The helper itself contains both marker literals (typo-guard).
#   5. The helper performs the splice with the canonical regex.
#   6. The helper emits the NOTICE-on-missing-markers fallback.
#   7. The helper invokes `gh pr edit --body-file` (safer than --body for
#      multi-line content).
check_fixed run-plan "pr body: start marker"          '<!-- run-plan:progress:start -->'
check_fixed run-plan "pr body: end marker"            '<!-- run-plan:progress:end -->'
check_fixed run-plan "phase4: references sync-pr-body-progress.sh helper" \
            'sync-pr-body-progress.sh'
check_executable run-plan "scripts/sync-pr-body-progress.sh" \
                 "phase4: helper exists+executable"
check_in_file run-plan "scripts/sync-pr-body-progress.sh" \
              "phase4 helper: start marker literal" \
              'run-plan:progress:start'
check_in_file run-plan "scripts/sync-pr-body-progress.sh" \
              "phase4 helper: end marker literal" \
              'run-plan:progress:end'
check_in_file run-plan "scripts/sync-pr-body-progress.sh" \
              "phase4 helper: splice between markers" \
              '\(\.\*\$START_MARKER\)\(\.\*\)\(\$END_MARKER\.\*\)'
check_in_file run-plan "scripts/sync-pr-body-progress.sh" \
              "phase4 helper: NOTICE on missing markers" \
              'markers not found.*expected for PRs not opened by /run-plan'
check_in_file run-plan "scripts/sync-pr-body-progress.sh" \
              "phase4 helper: gh pr edit --body-file" \
              'gh pr edit.*--body-file|"\$GH" pr edit.*--body-file'
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

# VERIFIER_AGENT_FIX Phase 2 — /run-plan must dispatch the verifier subagent
# explicitly via subagent_type:"verifier" (D'' Layer 0 timeout-injection)
# AND pipe the verifier response through Layer 3 validation. Tripwire:
# any future refactor that drops the explicit subagent_type or removes
# the Layer 3 invocation reverts the fix and re-exposes the bg+Monitor
# recovery reflex that PR #185/#186 surfaced.
check_fixed run-plan "verifier subagent dispatch"     'subagent_type: "verifier"'
check_fixed run-plan "Layer 3 invocation"             'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"'
check_fixed run-plan "Failure Protocol STOP message"  'STOP: verifier returned without meaningful results'
check_fixed run-plan "dispatcher attribution clarifier" 'Dispatcher: the orchestrator (top-level `/run-plan`), not the verifier subagent'

echo ""
echo "=== /run-plan — structural landmarks ==="
check run-plan "Phase 5b header"    '^## Phase 5b'
check run-plan "Phase 5c header"    '^## Phase 5c'
check run-plan "Phase 6 header"     '^## Phase 6'
check run-plan "Failure Protocol"   '^## Failure Protocol'

echo ""
echo "=== /run-plan — shell idioms ==="
check_fixed run-plan "create-worktree invocation" 'bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh"'
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
check_fixed commit "write-landed"             'bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/write-landed.sh"'
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
check_fixed do "sanitize-pipeline-id"         'bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh"'
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
echo "=== /do — issue-claim wiring (claim-work-item Phase 2 / W2.2 + W2.3) ==="
# /do parses the issue number(s) into ISSUE_NUMS (reachable only via
# --force triage override). Acquire uses the $CLAIM_HELPER indirection
# (CLAIM_HELPER=...claim-issue.sh + per-issue `bash "$CLAIM_HELPER"
# acquire "$ISSUE_NUM"` inside a fan-out loop over `"${ISSUE_NUMS[@]}"`);
# release iterates the array and inlines the literal claim-issue.sh path.
# The sentinels grep the EXISTING patterns so a future edit dropping the
# wiring FAILS the test. These are positive assertions only.
# Multi-issue parser (#863): ISSUE_NUMS array populated from leading
# anchored + separator-delimited subsequent matches. BASH_REMATCH index
# is `[4]` after #920 added an optional `issue[s]?:?` filler capture group
# between the close-keyword and `#N`.
check_fixed do "SKILL.md parses ISSUE_NUMS array"     'ISSUE_NUMS+=("${BASH_REMATCH[4]}")'
check_fixed do "SKILL.md back-compat ISSUE_NUM"       'ISSUE_NUM="${ISSUE_NUMS[0]:-}"'
# worktree mode: acquire after PIPELINE_ID + worktree; release in Phase 5 Report (SKILL.md).
check_in_file do "modes/worktree.md" "worktree CLAIM_HELPER"     'CLAIM_HELPER=.*fix-issues/scripts/claim-issue\.sh'
check_in_file do "modes/worktree.md" "worktree fan-out acquire"  'for ISSUE_NUM in "\${ISSUE_NUMS\[@\]}"'
check_in_file do "modes/worktree.md" "worktree acquire call"     'bash "\$CLAIM_HELPER" acquire "\$ISSUE_NUM"'
check_in_file do "modes/direct.md"   "direct CLAIM_HELPER"       'CLAIM_HELPER=.*fix-issues/scripts/claim-issue\.sh'
check_in_file do "modes/direct.md"   "direct fan-out acquire"    'for ISSUE_NUM in "\${ISSUE_NUMS\[@\]}"'
check_in_file do "modes/direct.md"   "direct acquire call"       'bash "\$CLAIM_HELPER" acquire "\$ISSUE_NUM"'
check_in_file do "modes/pr.md"       "pr CLAIM_HELPER"           'CLAIM_HELPER=.*fix-issues/scripts/claim-issue\.sh'
check_in_file do "modes/pr.md"       "pr fan-out acquire"        'for ISSUE_NUM in "\${ISSUE_NUMS\[@\]}"'
check_in_file do "modes/pr.md"       "pr acquire call"           'bash "\$CLAIM_HELPER" acquire "\$ISSUE_NUM"'
# Partial-acquire rollback: each acquire site releases prior claims on
# rc=10/11/2/* (issue #863).
check_in_file do "modes/worktree.md" "worktree rollback"  'for _RB in "\${_ACQUIRED\[@\]}"'
check_in_file do "modes/direct.md"   "direct rollback"    'for _RB in "\${_ACQUIRED\[@\]}"'
check_in_file do "modes/pr.md"       "pr rollback"        'for _RB in "\${_ACQUIRED\[@\]}"'
# Release: /do worktree/direct release in SKILL.md Phase 5 Report + error
# handling; /do pr releases inline (early-exit) + in the finalize block.
# Release iterates ISSUE_NUMS via `for _ISSUE_N in "${ISSUE_NUMS[@]}"`.
check_fixed do "SKILL.md release fan-out"        'for _ISSUE_N in "${ISSUE_NUMS[@]}"'
check_fixed do "SKILL.md release call"           'claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"'
check_in_file do "modes/pr.md"       "pr release fan-out"  'for _ISSUE_N in "\${ISSUE_NUMS\[@\]}"'
check_in_file do "modes/pr.md"       "pr release call"     'claim-issue\.sh" release "\$_ISSUE_N" --require-pipeline "\$PIPELINE_ID"'

echo ""
echo "=== /fix-issues — behavior contracts ==="
check       fix-issues "stop-precedence"            'Takes precedence|takes precedence'
check_fixed fix-issues "landing-default"            'LANDING_MODE="cherry-pick"'
check       fix-issues "direct+main_protected"      'direct mode is incompatible with main_protected'
check_fixed fix-issues "fix branch naming"          'fix/issue-'
check_fixed fix-issues "pr worktree path"           '/tmp/${PROJECT_NAME}-fix-issue-'
check_fixed fix-issues "sprint-id format"           'SPRINT_ID="sprint-'
check_fixed fix-issues "pipeline-id format"         'PIPELINE_ID="fix-issues.'
check_fixed fix-issues "sanitize-pipeline-id"       'bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh"'
check_fixed fix-issues "recover sprint-id"          'SPRINT_ID="${PIPELINE_ID#fix-issues.'
check       fix-issues "3 agent dispatch cap"       'most 3 worktree agents per message'
check       fix-issues "agent 1-hour timeout"       'Agent timeout: 1 hour|1.hour.*timeout'
check       fix-issues "skip-conflicts protocol"    'cherry-pick CONFLICTS|skip-and-continue'
check       fix-issues "verbatim issue body"        'verbatim issue body|gh issue view'
# Issue #510: Tier-1 hash-registration directive must ship in the
# impl-prompt template. Without this prose, orchestrators improvise
# per-invocation injections (sprint-20260520 #468, #474 each lost a CI
# cycle when the injection was missing). The two anchors below assert
# both the registry path AND the discipline label are present in source.
check_fixed fix-issues "tier1 registry path"        'tier1-shipped-hashes.txt'
check       fix-issues "tier1 discipline label"     'Tier-1 file discipline'
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
check       fix-issues "auto-gating prose"          'Auto-flag gating depends on landing mode'
check_fixed fix-issues "auto-gating clarified to merge" '(auto-merge) pass-through to `/land-pr` per landing mode'
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
# #444 — Phase 2 triage gains a 6th "Author decision needed" bucket for
# blurbs whose **Action now:** value is `none` or `/draft-plan` (the
# blurb defers tier choice to the human). And the orchestrator MUST
# print a structured per-fire user-facing summary on EVERY fire —
# productive AND no-actionable — so stable skips surface instead of
# silent cron no-ops. Mirror coverage is enforced by the hash-parity
# check later in this script ("Per-skill version mirror parity"); these
# tripwires assert the SOURCE carries the prose. Drift in either
# direction (rename, deletion, mirror divergence) trips a tripwire.
check_fixed fix-issues "6th triage bucket (Author decision needed)" 'Author decision needed'
check_fixed fix-issues "Per-fire user-facing summary section"       'Per-fire user-facing summary'
check       fix-issues "summary references both branches"           'productive branch.*no-actionable|no-actionable.*productive'
check_in_file fix-issues modes/sprint.md "summary referenced from no-actionable exit" \
  'per-fire user-facing summary'
check_in_file .claude/skills/fix-issues modes/sprint.md "mirror has 6th bucket"               'Author decision needed'
check_in_file .claude/skills/fix-issues modes/sprint.md "mirror has summary section heading"  'Per-fire user-facing summary'
# WI 4.6 RELOCATE: the `if [ "$AUTO_FLAG" != "true" ]` literal guard
# now lives in /land-pr's pr-merge.sh (Phase 1B WI 1.6). Verify it
# stays there.
check_in_file land-pr scripts/pr-merge.sh "auto-merge AUTO_FLAG guard" 'if \[ "\$AUTO_FLAG" != "true" \]; then'

# Guard recently-reverted content (see #704, #729, #735).
# These blocks have been lost-then-restored across rapid PR landings; pin
# them so any future accidental deletion fails CI. The `check` helper greps
# the whole skill tree recursively, so each pin survives RESTRUCTURE moves
# (e.g. the staleness step now lives in subcommands/stop-next.md after #740).
check fix-issues        "next-section staleness step (#729/#735)"  'Peek at the Ready queue'
check zskills-dashboard "ZSKILLS_DASHBOARD_ROOT contract (#704/#735)" 'ZSKILLS_DASHBOARD_ROOT'

echo ""
echo "=== auto grammar ==="

# Issue #810 — --force form normalization across the force-accepting skills.
# Bare positional `force` was the form on /cleanup-merged;
# /do and /work-on-plans were already on the dashed form. Now all
# accept `--force`. This block pins the dashed parser arm on every
# skill that accepts a force override, and pins the absence of any
# bare-`force)` case branch on the one that previously had one.
#
# /do — pre-flight bash-regex parser detects --force out of $ARGUMENTS.
check_fixed do            "--force pre-flight parser (issue #810)" '(^|[[:space:]])--force($|[[:space:]])'

# /work-on-plans — synopsis advertises --force.
check_fixed work-on-plans "--force in synopsis (issue #810)" '[--force]'

# /cleanup-merged — dashed parser arm; no bare 'force)' arm; --force
# advertised in argument-hint.
check_fixed cleanup-merged "--force) parser arm (issue #810)" '--force) FORCE=1'
check_not   cleanup-merged "no bare 'force)' arm (issue #810)" '^[[:space:]]*force\)[[:space:]]+FORCE=1'
check_not   cleanup-merged "argument-hint NO [--force] (#961 reverses #810)" 'argument-hint:.*--force'

check_fixed run-plan    "AUTO_FLAG init"        'AUTO_FLAG=0'

check_fixed fix-issues  "AUTO_FLAG init"        'AUTO_FLAG=0'

check_fixed do          "AUTO_FLAG init"        'AUTO_FLAG=0'

echo ""
echo "=== /fix-issues — structural landmarks ==="
check fix-issues "Phase 3"           '^## Phase 3'
check fix-issues "Phase 6 Land"      '^## Phase 6'
check fix-issues "Failure Protocol"  '^## Failure Protocol'

echo ""
echo "=== /investigate — issue-claim wiring (claim-work-item Phase 2 / W2.1) ==="
# /investigate synthesizes PIPELINE_ID="investigate.issue-$N" (no pipeline
# id of its own), acquires at the #N parse (Phase 1 step 1) before any
# reproduction work, releases on the success-path Report bash block + the
# explicit per-STOP prose at each abandon point.
check_fixed investigate "synthesizes PIPELINE_ID"  'sanitize-pipeline-id.sh" "investigate.issue-$N"'
check_fixed investigate "CLAIM_HELPER assignment"  'CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"'
check_fixed investigate "acquires issue claim"     'bash "$CLAIM_HELPER" acquire "$N" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"'
check_fixed investigate "releases issue claim"     'claim-issue.sh" release "$N" --require-pipeline "$PIPELINE_ID"'

echo ""
echo "=== /draft-plan, /refine-plan, /draft-tests — auto flag + /land-pr dispatch (#581) ==="
# Issue #581: the three drafting skills create worktrees but had no
# auto-landing path. Under `execution.landing: pr` + `main_protected: true`,
# /draft-plan → /run-plan silently failed because the plan file was
# committed in the worktree, not on main. Each skill now recognizes the
# positional `auto` token and dispatches /land-pr after the Phase-N
# worktree auto-commit.
for skill in draft-plan refine-plan draft-tests; do
  check_fixed "$skill" "AUTO_FLAG init"          'AUTO_FLAG=0'
  check       "$skill" "auto token detection"    '\[aA\]\[uU\]\[tT\]\[oO\]'
  check_fixed "$skill" "dispatches /land-pr"     'land-pr'
  check_fixed "$skill" "AUTO_FLAG gates dispatch" '${AUTO_FLAG:-0}" = "1"'
  check_fixed "$skill" "Skill tool dispatch line" 'Skill: { skill: "land-pr"'
  check_fixed "$skill" "--auto flag passed to land-pr" '--auto'
  check       "$skill" "argument-hint contains auto" 'argument-hint:.*\[auto\]'
done

echo ""
echo "=== parent→child auto propagation — closure for #581 / PR #642 (#648) ==="
# Issue #648: #581's child-side fix made /draft-plan, /refine-plan,
# /draft-tests recognize positional `auto` and dispatch /land-pr.
# But three parent dispatch sites didn't propagate `auto` to the
# children, so under /research-and-go (or /run-plan auto pr with a stale
# plan), the child skill commits in its worktree and never lands on
# main. Each parent skill MUST:
#   (a) resolve $AUTO_ARG from its own auto-detect block, and
#   (b) thread $AUTO_ARG (or literal `auto`) into every dispatch string
#       targeting a /draft-* or /refine-* child.
for parent in research-and-plan run-plan; do
  check_fixed "$parent" "AUTO_ARG resolver present"      'AUTO_ARG'
done
# /research-and-plan dispatches /draft-plan; site MUST carry $AUTO_ARG.
check       research-and-plan "/draft-plan dispatch threads \$AUTO_ARG" \
  '/draft-plan .*\$AUTO_ARG'
# /run-plan dispatches /refine-plan; sites MUST carry $AUTO_ARG.
check       run-plan "/refine-plan dispatch threads \$AUTO_ARG" \
  '/refine-plan <plan-file>\$AUTO_ARG'
# Both dispatch arms (Phase 1 textual-staleness and arithmetic-drift checks)
# share the `/refine-plan <plan-file>$AUTO_ARG` literal. Assert >= 2 across
# the skill tree (SKILL.md + modes/execute-phase.md after the #725 split).
# (The non-dispatch recommendation prose at "Recommend running
# `/refine-plan <plan-file>` after close-out" uses no `$` after, so the
# fixed-string `<plan-file>$AUTO_ARG` distinguishes dispatches reliably.)
SITE_COUNT=$(grep -rF '/refine-plan <plan-file>$AUTO_ARG' "$REPO_ROOT/skills/run-plan/" --include='*.md' | wc -l)
if [ "$SITE_COUNT" -ge 2 ]; then
  pass "[run-plan] both /refine-plan dispatch arms thread \$AUTO_ARG (count=$SITE_COUNT)"
else
  fail "[run-plan] both /refine-plan dispatch arms thread \$AUTO_ARG" \
    "expected ≥2 occurrences, found $SITE_COUNT"
fi

echo ""
echo "=== implementer subagent — impl-dispatch site pins (Verifier-cannot-run symmetry) ==="
# Each impl-class dispatch (orchestrator asks a sub-agent to write code,
# run tests, and/or commit) MUST declare `subagent_type: "implementer"`.
# The implementer agent at .claude/agents/implementer.md clones verifier's
# frontmatter inject-bash-timeout.sh hook, so the impl agent's Bash calls
# auto-extend to 600s and never trigger the bg+Monitor stall pattern that
# hangs the dispatch at "Tests are running. Let me wait for the monitor."
#
# Scoped per-file (check_in_file_near) so adding the directive to an
# unrelated file inside the skill tree doesn't satisfy the assertion —
# each dispatch site is verified independently. Issue #517: the
# `_near` form requires the pin literal to appear within 10 lines of
# the `Agent` keyword (i.e., near a real dispatch directive); a
# whole-file `grep -E` would let a demoted dispatch site (general-purpose)
# pass as long as ANY footnote/comment elsewhere mentioned the pin.
check_in_file_near run-plan    "modes/execute-phase.md"     "impl-dispatch pins implementer" 'subagent_type: "implementer"' 'Agent' 0
check_in_file_near run-plan    "modes/pr.md"                "fix-cycle pins implementer"     'subagent_type: "implementer"' 'Agent' 0
check_in_file_near fix-issues  "modes/sprint.md"             "fix-agent pins implementer"     'subagent_type: "implementer"' 'Agent' 0
check_in_file_near fix-issues  "modes/pr.md"                "fix-cycle pins implementer"     'subagent_type: "implementer"' 'Agent' 0
check_in_file_near land-pr     "references/fix-cycle-agent-prompt-template.md" "template pins implementer" 'subagent_type: "implementer"' 'Agent' 0
check_in_file_near do          "modes/pr.md"                "impl+fix-cycle pins implementer" 'subagent_type: "implementer"' 'Agent' 0

# /draft-plan — quiz-mode conditional-load wiring (DRAFT_PLAN_QUIZ_MODE Phase
# 3, R9; #944 collapsed the two booleans into STEERING_MODE). The interactive
# quiz interview is gated behind STEERING_MODE = quiz and its procedure lives
# in references/quiz.md, read via a conditional-load directive. There is no
# orphan-reference gate today, so this is the ONLY automated check that
# exercises the new wiring. Use check_in_file_near (NOT a bare grep for
# 'references/quiz.md') so the assertion verifies CO-OCCURRENCE: the
# references/quiz.md reference must appear within 10 lines of a
# `STEERING_MODE = quiz` conditional token. A bare substring grep would still
# pass if the conditional guard were stripped (degraded to an unconditional
# read) or if the string survived only in a comment elsewhere; the _near form
# fails closed in both cases — removing the `STEERING_MODE = quiz`-guarded
# conditional load breaks it.
check_in_file_near draft-plan  "SKILL.md"                   "quiz conditional-load wiring" 'references/quiz.md' 'STEERING_MODE = quiz' 10

# Agent definition file exists with the expected frontmatter shape.
if [ -f "$REPO_ROOT/.claude/agents/implementer.md" ]; then
  pass "[.claude/agents/implementer.md] exists"
else
  fail "[.claude/agents/implementer.md] exists" "missing"
fi
if grep -q '^name: implementer$' "$REPO_ROOT/.claude/agents/implementer.md" 2>/dev/null; then
  pass "[.claude/agents/implementer.md] name: implementer"
else
  fail "[.claude/agents/implementer.md] name: implementer" "frontmatter mismatch"
fi
if grep -q 'inject-bash-timeout.sh' "$REPO_ROOT/.claude/agents/implementer.md" 2>/dev/null; then
  pass "[.claude/agents/implementer.md] hooks inject-bash-timeout.sh"
else
  fail "[.claude/agents/implementer.md] hooks inject-bash-timeout.sh" "Layer 0 hook reference missing"
fi

# Verifier agent scope-creep AC check guidance (Issue #448).
# Bare `git diff origin/main..HEAD --stat` shows symmetric file-set diff;
# when origin/main advances past the branch merge-base mid-verification
# (active-landing cadence), files added on origin appear as "deletions"
# in HEAD's diff and the verifier REJECTs with a destructive recovery
# path. The agent prose recommends commit-only or merge-base forms.
if grep -qF 'git show HEAD --stat' "$REPO_ROOT/.claude/agents/verifier.md" 2>/dev/null; then
  pass "[.claude/agents/verifier.md] scope-creep: git show HEAD --stat"
else
  fail "[.claude/agents/verifier.md] scope-creep: git show HEAD --stat" "commit-only diff form missing"
fi
if grep -qF 'merge-base origin/main HEAD' "$REPO_ROOT/.claude/agents/verifier.md" 2>/dev/null; then
  pass "[.claude/agents/verifier.md] scope-creep: merge-base form"
else
  fail "[.claude/agents/verifier.md] scope-creep: merge-base form" "merge-base diff form missing"
fi

# Symmetric-diff anti-pattern absence in skills/ (Issue #557).
# The three-dot symmetric `main...<branch>` form has the same false-positive
# failure mode as the two-dot bare `origin/main..HEAD --stat` (issue #448):
# when origin/main advances past the branch merge-base mid-verification,
# files added on origin appear as "deletions" in HEAD's diff and the
# verifier REJECTs with a destructive recovery path. PR #453 fixed the
# agent file; this tripwire prevents any skill SKILL.md from re-introducing
# the orchestrator-side instruction that previously overrode the agent-file
# defense at `skills/run-plan/modes/execute-phase.md`. Scope: skills/**/*.md
# ONLY (not docs/ or issues/, where the literal appears in this issue's
# own blurb and sprint-report prose).
symmetric_hits=$(grep -rlE 'git (diff|log) (origin/)?main\.\.\.' "$REPO_ROOT/skills" --include='*.md' 2>/dev/null || true)
if [ -z "$symmetric_hits" ]; then
  pass "[skills/**/*.md] no symmetric-diff anti-pattern (git diff main...)"
else
  fail "[skills/**/*.md] no symmetric-diff anti-pattern (git diff main...)" "actionable symmetric-diff command appears in: $symmetric_hits"
fi

# Verifier test-output tally check (Issue #511).
# Scanning visible inline PASS lines is insufficient — the verifier must
# assert the canonical summary line (`Overall: N/M passed, F failed` from
# tests/run-all.sh) is PRESENT, that N == M and F == 0, and that N is not
# below the captured pre-impl baseline. Past failure 2026-05-18: verifier
# reported "3313/3313 passed" by counting inline PASS lines; final tally
# was 3311/3313 — two regressions slipped.
if grep -qF 'Overall: N/M passed' "$REPO_ROOT/.claude/agents/verifier.md" 2>/dev/null; then
  pass "[.claude/agents/verifier.md] tally check: Overall: N/M passed prose"
else
  fail "[.claude/agents/verifier.md] tally check: Overall: N/M passed prose" "summary-line assertion guidance missing"
fi
if grep -qF 'baseline_N' "$REPO_ROOT/.claude/agents/verifier.md" 2>/dev/null; then
  pass "[.claude/agents/verifier.md] tally check: baseline comparison"
else
  fail "[.claude/agents/verifier.md] tally check: baseline comparison" "baseline-comparison guidance missing"
fi
# Issue #575: the same canonical summary-line prose is mirrored into
# skills/run-plan/modes/execute-phase.md Phase 3 verifier-dispatch prompt.
# The .claude/agents/verifier.md check above is the agent-file pin; this
# assertion pins the run-plan execute-phase copy so a "prose
# simplification" revert of the verifier prompt cannot silently drop the
# tally directive from the run-plan workflow path (the prompt actually
# dispatched to the verifier subagent in PR mode).
if grep -qF 'Overall: N/M passed' "$REPO_ROOT/skills/run-plan/modes/execute-phase.md" 2>/dev/null; then
  pass "[skills/run-plan/modes/execute-phase.md] tally check: Overall: N/M passed prose"
else
  fail "[skills/run-plan/modes/execute-phase.md] tally check: Overall: N/M passed prose" "summary-line assertion guidance missing from Phase 3 verifier-dispatch prompt"
fi

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

# --- WI 6.1 (d) — All 7 callers dispatch /land-pr (4 impl + 3 drafting per #581) ---
# Substring match suffices because `land-pr` only appears in dispatch
# contexts inside the caller files (verified during Phase 2-5 migrations
# and #581's drafting-skill adoption).
# These checks duplicate the per-skill assertions above (run-plan,
# commit, do, fix-issues, draft-plan, refine-plan, draft-tests
# already each have their own `dispatches /land-pr` check) but consolidate
# them as a single cross-skill drift-prevention claim.
LAND_PR_CALLERS=(
  "skills/run-plan/modes/pr.md"
  "skills/commit/modes/pr.md"
  "skills/do/modes/pr.md"
  "skills/fix-issues/modes/pr.md"
  "skills/draft-plan/SKILL.md"
  "skills/refine-plan/SKILL.md"
  "skills/draft-tests/modes/land.md"
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
  pass "[cross-skill] all 7 callers reference /land-pr (dispatch present)"
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
  pass "[cross-skill] /land-pr dispatched at orchestrator level in all 7 callers (no nested-Agent markers within ±15 lines)"
fi

echo ""
echo "=== LAND_PR_BYPASS_HARDENING — Phase 4 conformance tripwires ==="
# Phase 4 of plan docs/plans/LAND_PR_BYPASS_HARDENING.md. Locks structural
# defense: positive asserts that new caller code is present, fence-survival
# asserts that finalize stays inside the caller-loop bash fence, negative
# asserts that no skill source contains a bypass pattern (gh pr create /
# gh pr merge --auto outside skills/land-pr/scripts/).

# --- Caller-loop anchor positions (per-file) ---
# Each caller has a `# === BEGIN CANONICAL /land-pr CALLER LOOP ===` and
# `# === END CANONICAL /land-pr CALLER LOOP ===` anchor pair. fix-issues
# is 2-space indented (it lives inside a per-issue loop wrapper) — use
# substring match (grep -nF) so indentation doesn't trip the locator.

# Mapping: caller-file → fulfilled-marker-basename (used for textual checks).
declare -A LANDPR_MARKER_BASENAME=(
  ["skills/commit/modes/pr.md"]="fulfilled.commit."
  ["skills/do/modes/pr.md"]="fulfilled.do."
  ["skills/fix-issues/modes/pr.md"]="fulfilled.fix-issues."
)

# Callers that get the new fulfilled.<skill>.<id> start-marker AND
# explicit-finalize block (commit/do/fix-issues). After issue #241 each
# ALSO has an in-fence explicit-finalize block — the trap-on-EXIT pattern
# was unreliable (fired on skill entry, not flow end). The in-fence check
# below treats all 3 callers uniformly.
NEW_CALLERS=(
  "skills/commit/modes/pr.md"
  "skills/do/modes/pr.md"
  "skills/fix-issues/modes/pr.md"
)

# All 3 caller files (positive --tracking-id= + requires.land-pr precedence
# asserts apply to all three).
ALL_CALLERS=(
  "skills/commit/modes/pr.md"
  "skills/do/modes/pr.md"
  "skills/fix-issues/modes/pr.md"
)

# Helper: get line number of "BEGIN CANONICAL ... " (substring match).
landpr_begin_line() {
  grep -nF "# === BEGIN CANONICAL /land-pr CALLER LOOP ===" "$1" | head -1 | cut -d: -f1
}
landpr_end_line() {
  grep -nF "# === END CANONICAL /land-pr CALLER LOOP ===" "$1" | head -1 | cut -d: -f1
}
# Helper: closing fence line AFTER given line N (allows leading whitespace
# per R-5-11 — future indented case must not silently slip through; current
# callers all use unindented closing fences).
landpr_close_fence_after() {
  local file="$1" after="$2"
  awk -v start="$after" 'NR>start && /^[[:space:]]*```[[:space:]]*$/ {print NR; exit}' "$file"
}

# --- Positive: each caller contains --tracking-id= between BEGIN and END ---
for caller in "${ALL_CALLERS[@]}"; do
  caller_path="$REPO_ROOT/$caller"
  if [ ! -f "$caller_path" ]; then
    fail "[bypass-hardening] $caller --tracking-id= in caller loop" "file does not exist"
    continue
  fi
  begin=$(landpr_begin_line "$caller_path")
  end=$(landpr_end_line "$caller_path")
  if [ -z "$begin" ] || [ -z "$end" ]; then
    fail "[bypass-hardening] $caller --tracking-id= in caller loop" "BEGIN/END anchor not found (begin=$begin end=$end)"
    continue
  fi
  if sed -n "${begin},${end}p" "$caller_path" | grep -qF -- '--tracking-id='; then
    pass "[bypass-hardening] $caller contains --tracking-id= between BEGIN/END anchors"
  else
    fail "[bypass-hardening] $caller contains --tracking-id= between BEGIN/END anchors" "--tracking-id= literal not found in caller-loop region"
  fi
done

# --- Positive: each caller has a requires.land-pr.* write BEFORE LAND_ARGS= ---
# R-1-3 textual-precedence assert. fix-issues writes the marker inside its
# per-issue loop, BEFORE LAND_ARGS=.
for caller in "${ALL_CALLERS[@]}"; do
  caller_path="$REPO_ROOT/$caller"
  [ ! -f "$caller_path" ] && continue
  req_line=$(grep -nE 'requires\.land-pr\.' "$caller_path" | head -1 | cut -d: -f1)
  args_line=$(grep -nE '^[[:space:]]*LAND_ARGS=' "$caller_path" | head -1 | cut -d: -f1)
  if [ -z "$req_line" ] || [ -z "$args_line" ]; then
    fail "[bypass-hardening] $caller requires.land-pr.* precedes LAND_ARGS=" "req_line=$req_line args_line=$args_line"
    continue
  fi
  if [ "$req_line" -lt "$args_line" ]; then
    pass "[bypass-hardening] $caller requires.land-pr.* write (L$req_line) precedes LAND_ARGS= (L$args_line)"
  else
    fail "[bypass-hardening] $caller requires.land-pr.* write precedes LAND_ARGS=" "req at L$req_line is NOT before LAND_ARGS at L$args_line"
  fi
done

# --- Positive: NEW callers (commit, do, fix-issues) have fulfilled.<skill>.
# start-marker write block. ---
for caller in "${NEW_CALLERS[@]}"; do
  caller_path="$REPO_ROOT/$caller"
  basename_marker="${LANDPR_MARKER_BASENAME[$caller]}"
  [ ! -f "$caller_path" ] && continue
  # The block writes the marker via `cat > "$TRACK_DIR/<basename>..." <<MARK`
  # or similar; the literal `fulfilled.<skill>.` substring suffices.
  if grep -qF -- "$basename_marker" "$caller_path"; then
    pass "[bypass-hardening] $caller writes $basename_marker start-marker"
  else
    fail "[bypass-hardening] $caller writes $basename_marker start-marker" "literal '$basename_marker' not found"
  fi
done

# --- Fence-survival assert (R-4-7 / DA-4-4 + R-5-11 + DA-5-4) ---
# For each new caller: locate END anchor, locate next closing
# fence, assert that the relevant sed/rm finalize lines fall BETWEEN them.
# Then counter-assert that no out-of-fence duplicate exists below the
# closing fence (matched on the same marker basename).
FENCE_CALLERS=(
  "skills/commit/modes/pr.md"
  "skills/do/modes/pr.md"
  "skills/fix-issues/modes/pr.md"
)
for caller in "${FENCE_CALLERS[@]}"; do
  caller_path="$REPO_ROOT/$caller"
  basename_marker="${LANDPR_MARKER_BASENAME[$caller]}"
  if [ ! -f "$caller_path" ]; then
    fail "[bypass-hardening] $caller fence-survival" "file does not exist"
    continue
  fi
  end_line=$(landpr_end_line "$caller_path")
  if [ -z "$end_line" ]; then
    fail "[bypass-hardening] $caller fence-survival" "END anchor not found"
    continue
  fi
  close_fence=$(landpr_close_fence_after "$caller_path" "$end_line")
  if [ -z "$close_fence" ]; then
    fail "[bypass-hardening] $caller fence-survival" "no closing fence found after END anchor at L$end_line"
    continue
  fi

  # Region IN-FENCE between END anchor and closing ```.
  region=$(sed -n "${end_line},${close_fence}p" "$caller_path")

  # For all callers (issue #241 unification): both `sed -i "s/^status:
  # started$/status:` and `rm -f .*requires.land-pr.` MUST appear in the
  # in-fence region. After #241 each has the same in-fence
  # explicit-finalize block.
  has_sed_in=$(echo "$region" | grep -cE 'sed -i "s/\^status: started\$/status:' || true)
  has_rm_in=$(echo "$region"  | grep -cE 'rm -f .*requires\.land-pr\.' || true)

  if [ "$has_sed_in" -ge 1 ] && [ "$has_rm_in" -ge 1 ]; then
    pass "[bypass-hardening] $caller explicit-finalize in-fence (sed+rm between L$end_line..L$close_fence)"
  else
    fail "[bypass-hardening] $caller explicit-finalize in-fence" "sed_hits=$has_sed_in rm_hits=$has_rm_in between END L$end_line and close-fence L$close_fence"
  fi

  # Counter-assert (DA-5-4): no duplicate finalize AFTER the closing fence.
  # Match on the same caller's marker basename so we don't false-positive
  # on unrelated fulfilled.* lines elsewhere in the file.
  after_close=$((close_fence + 1))
  tail_region=$(tail -n +"$after_close" "$caller_path")
  dup_sed=$(echo "$tail_region" | grep -cE "sed -i \"s/\^status: started\\\$/status:.*${basename_marker}" || true)
  dup_rm=$(echo "$tail_region"  | grep -cE "rm -f .*requires\.land-pr\." || true)

  if [ "$dup_sed" -eq 0 ] && [ "$dup_rm" -eq 0 ]; then
    pass "[bypass-hardening] $caller no duplicate finalize after close-fence L$close_fence (sed=$dup_sed rm=$dup_rm)"
  else
    fail "[bypass-hardening] $caller no duplicate finalize after close-fence" "dup_sed=$dup_sed dup_rm=$dup_rm below L$close_fence (status-rewrite in a stray fence would have unset \$LAND_OUTCOME)"
  fi
done

# --- /run-plan modes/pr.md: requires.land-pr cleanup AFTER END anchor ---
# DA-3-4 fix per spec.
rp_pr="$REPO_ROOT/skills/run-plan/modes/pr.md"
if [ -f "$rp_pr" ]; then
  end_line=$(landpr_end_line "$rp_pr")
  if [ -n "$end_line" ]; then
    tail_region=$(tail -n +"$end_line" "$rp_pr")
    if echo "$tail_region" | grep -qE 'rm -f .*requires\.land-pr\.'; then
      pass "[bypass-hardening] run-plan/modes/pr.md requires.land-pr cleanup AFTER END anchor (L$end_line)"
    else
      fail "[bypass-hardening] run-plan/modes/pr.md requires.land-pr cleanup AFTER END anchor" "no 'rm -f .*requires.land-pr.' below L$end_line"
    fi
  else
    fail "[bypass-hardening] run-plan/modes/pr.md END anchor present" "END anchor not found"
  fi
fi

# --- /run-plan SKILL.md: BRANCH_NAME_FOR_MARKER + fence-top re-derivation ---
# Per spec (DA-2-2 + R-3-1 + R-4-2 / DA-4-1 + DA-5-8): the requires.land-pr
# marker-write fence (~lines 831-890) writes `branch: %s` derived from
# `${BRANCH_PREFIX}${PLAN_SLUG}` via the new variable BRANCH_NAME_FOR_MARKER.
#
# Assert 1: BRANCH_NAME_FOR_MARKER= exists somewhere in the file (the new
# variable name introduced by this plan).
# Assert 2: BRANCH_PREFIX="feat/" AND PLAN_SLUG=$(basename both fall between
# the OPENING ``` of the fence containing BRANCH_NAME_FOR_MARKER= and the
# BRANCH_NAME_FOR_MARKER= line itself (fence-top re-derivation discipline,
# R-5-1).
# Assert 3: BRANCH_NAME_FOR_MARKER= line appears BEFORE the
# requires.land-pr.$TRACKING_ID printf line.
rp_skill="$REPO_ROOT/skills/run-plan/SKILL.md"
if [ -f "$rp_skill" ]; then
  # Assert 1.
  bnfm_line=$(grep -nE '^[[:space:]]*BRANCH_NAME_FOR_MARKER=' "$rp_skill" | head -1 | cut -d: -f1)
  if [ -n "$bnfm_line" ]; then
    pass "[bypass-hardening] run-plan SKILL.md BRANCH_NAME_FOR_MARKER= assignment exists (L$bnfm_line)"
  else
    fail "[bypass-hardening] run-plan SKILL.md BRANCH_NAME_FOR_MARKER= assignment exists" "no BRANCH_NAME_FOR_MARKER= line found"
  fi

  # Determine fence boundaries containing $bnfm_line.
  if [ -n "$bnfm_line" ]; then
    # Opening ``` line — most-recent ```bash or ``` (with leading whitespace
    # tolerated) BEFORE $bnfm_line.
    open_fence=$(awk -v end="$bnfm_line" 'NR<end && /^[[:space:]]*```/ {last=NR} END{print last}' "$rp_skill")
    # Closing ``` line AFTER bnfm — first ``` line after $bnfm_line.
    close_fence=$(awk -v start="$bnfm_line" 'NR>start && /^[[:space:]]*```[[:space:]]*$/ {print NR; exit}' "$rp_skill")

    # Locate requires.land-pr.$TRACKING_ID printf line.
    req_printf_line=$(grep -nE 'requires\.land-pr\.\$TRACKING_ID' "$rp_skill" | head -1 | cut -d: -f1)

    # Assert 2: BRANCH_PREFIX="feat/" AND PLAN_SLUG=$(basename both
    # appear between open_fence and bnfm_line.
    bp_line=$(awk -v lo="$open_fence" -v hi="$bnfm_line" 'NR>lo && NR<hi && /^[[:space:]]*BRANCH_PREFIX="feat\/"/ {print NR; exit}' "$rp_skill")
    ps_line=$(awk -v lo="$open_fence" -v hi="$bnfm_line" 'NR>lo && NR<hi && /^[[:space:]]*PLAN_SLUG=\$\(basename/ {print NR; exit}' "$rp_skill")
    if [ -n "$bp_line" ] && [ -n "$ps_line" ]; then
      pass "[bypass-hardening] run-plan SKILL.md fence-top re-derivation: BRANCH_PREFIX (L$bp_line) + PLAN_SLUG (L$ps_line) inside fence L$open_fence..L$bnfm_line"
    else
      fail "[bypass-hardening] run-plan SKILL.md fence-top re-derivation discipline" "BRANCH_PREFIX line=$bp_line, PLAN_SLUG line=$ps_line in fence-open=$open_fence..bnfm=$bnfm_line (R-5-1)"
    fi

    # Assert 3: BRANCH_NAME_FOR_MARKER= precedes requires.land-pr.$TRACKING_ID
    # printf line.
    if [ -n "$req_printf_line" ] && [ "$bnfm_line" -lt "$req_printf_line" ]; then
      pass "[bypass-hardening] run-plan SKILL.md BRANCH_NAME_FOR_MARKER= (L$bnfm_line) precedes requires.land-pr.\$TRACKING_ID printf (L$req_printf_line)"
    else
      fail "[bypass-hardening] run-plan SKILL.md BRANCH_NAME_FOR_MARKER= textual precedence" "bnfm=$bnfm_line, req_printf=$req_printf_line (must have bnfm < req_printf)"
    fi
  fi

  # The branch value in the printf format string must derive from
  # ${BRANCH_PREFIX}${PLAN_SLUG} (not from `git symbolic-ref` or
  # $BRANCH_NAME). Anchor on the assignment.
  if grep -qE '^[[:space:]]*BRANCH_NAME_FOR_MARKER="\$\{BRANCH_PREFIX\}\$\{PLAN_SLUG\}"' "$rp_skill"; then
    pass "[bypass-hardening] run-plan SKILL.md BRANCH_NAME_FOR_MARKER derives from \${BRANCH_PREFIX}\${PLAN_SLUG}"
  else
    fail "[bypass-hardening] run-plan SKILL.md BRANCH_NAME_FOR_MARKER derives from \${BRANCH_PREFIX}\${PLAN_SLUG}" "no 'BRANCH_NAME_FOR_MARKER=\"\${BRANCH_PREFIX}\${PLAN_SLUG}\"' line"
  fi

  # The printf format string must include `branch:`.
  if grep -nE 'printf .*skill: land-pr.*\\nbranch: %s\\n' "$rp_skill" > /dev/null; then
    pass "[bypass-hardening] run-plan SKILL.md requires.land-pr printf includes 'branch: %s'"
  else
    fail "[bypass-hardening] run-plan SKILL.md requires.land-pr printf includes 'branch: %s'" "no 'skill: land-pr\\nparent: run-plan\\n... branch: %s' format string match"
  fi
fi

# --- Settings.json contains hook entry ---
if [ -f "$REPO_ROOT/.claude/settings.json" ] && grep -qF 'block-bypassed-land-pr.sh' "$REPO_ROOT/.claude/settings.json"; then
  pass "[bypass-hardening] .claude/settings.json registers block-bypassed-land-pr.sh"
else
  fail "[bypass-hardening] .claude/settings.json registers block-bypassed-land-pr.sh" "literal 'block-bypassed-land-pr.sh' not found in settings.json"
fi

# --- Hook is executable + inlines is_gh_pr_subcommand ---
hook_path="$REPO_ROOT/hooks/block-bypassed-land-pr.sh"
if [ -x "$hook_path" ]; then
  pass "[bypass-hardening] hooks/block-bypassed-land-pr.sh is executable"
else
  fail "[bypass-hardening] hooks/block-bypassed-land-pr.sh is executable" "not present or not +x: $hook_path"
fi
if [ -f "$hook_path" ] && grep -qE '^is_gh_pr_subcommand\(\)' "$hook_path"; then
  pass "[bypass-hardening] hooks/block-bypassed-land-pr.sh contains 'is_gh_pr_subcommand()' header line"
else
  fail "[bypass-hardening] hooks/block-bypassed-land-pr.sh contains 'is_gh_pr_subcommand()' header" "header not found"
fi

# --- STOP-message script contains ASCII anchors ---
msg_script="$REPO_ROOT/scripts/land-pr-bypass-message.sh"
if [ -f "$msg_script" ]; then
  if grep -qF 'STOP: direct gh pr' "$msg_script"; then
    pass "[bypass-hardening] land-pr-bypass-message.sh contains 'STOP: direct gh pr' anchor"
  else
    fail "[bypass-hardening] land-pr-bypass-message.sh contains 'STOP: direct gh pr' anchor" "anchor not found"
  fi
  if grep -qF 'outside a caller skill' "$msg_script"; then
    pass "[bypass-hardening] land-pr-bypass-message.sh contains Pattern 1 'outside a caller skill' anchor"
  else
    fail "[bypass-hardening] land-pr-bypass-message.sh contains Pattern 1 'outside a caller skill' anchor" "anchor not found"
  fi
  if grep -qF 'declared an intent to' "$msg_script"; then
    pass "[bypass-hardening] land-pr-bypass-message.sh contains Pattern 2 'declared an intent to' anchor (caller-declared-intent framing)"
  else
    fail "[bypass-hardening] land-pr-bypass-message.sh contains Pattern 2 caller-intent anchor" "anchor not found"
  fi
else
  fail "[bypass-hardening] scripts/land-pr-bypass-message.sh exists" "missing"
fi

# --- Negative asserts (DA-1-5 + R-4-3 / DA-4-3 + R-5-2 / DA-5-2 + R-5-3 / DA-5-1) ---
# Pattern 1: `gh pr (create|merge --auto)` in shell-command position.
# Recursive scope across skills/*.md; the --include='*.md' carve-out
# excludes skills/land-pr/scripts/*.sh where the sanctioned invocations
# live. Excludes comment lines and echo/printf prose.
p1_hits=$(grep -rnE "(^|;|\|\||&&)[[:space:]]*gh pr (create|merge[^\`]*--auto)([[:space:]]|$)" \
  "$REPO_ROOT/skills/" --include='*.md' 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(echo|printf)[[:space:]]' || true)
if [ -z "$p1_hits" ]; then
  pass "[bypass-hardening] negative: no inline 'gh pr create|merge --auto' in skill SKILL.md sources (Pattern 1, R-4-3/R-5-2/R-5-3)"
else
  fail "[bypass-hardening] negative: no inline 'gh pr create|merge --auto' (Pattern 1)" "$(echo "$p1_hits" | head -5 | tr '\n' '|')"
fi

# Pattern 2: bash -c '...gh pr create...' / sh -c '...gh pr merge --auto...'
p2_hits=$(grep -nrE "(bash|sh)[[:space:]]+-c[[:space:]]*['\"][^'\"]*gh pr (create|merge[^'\"]*--auto)" "$REPO_ROOT/skills/" 2>/dev/null || true)
if [ -z "$p2_hits" ]; then
  pass "[bypass-hardening] negative: no 'bash -c'/'sh -c' wrapping gh pr create|merge --auto (Pattern 2)"
else
  fail "[bypass-hardening] negative: no 'bash -c'/'sh -c' wrapping gh pr (Pattern 2)" "$(echo "$p2_hits" | head -5 | tr '\n' '|')"
fi

# Pattern 3: eval '...gh pr create...' / eval "...gh pr merge --auto..."
p3_hits=$(grep -nrE "eval[[:space:]]+['\"][^'\"]*gh pr (create|merge[^'\"]*--auto)" "$REPO_ROOT/skills/" 2>/dev/null || true)
if [ -z "$p3_hits" ]; then
  pass "[bypass-hardening] negative: no 'eval' wrapping gh pr create|merge --auto (Pattern 3)"
else
  fail "[bypass-hardening] negative: no 'eval' wrapping gh pr (Pattern 3)" "$(echo "$p3_hits" | head -5 | tr '\n' '|')"
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

# --- Issue #188 regression guard: pr-push-and-create.sh must NOT use
# bare `git push` (which silently no-ops when CWD's current branch
# differs from $BRANCH). The push must always be `git push -u origin
# "$BRANCH"` explicitly.
check_not_in_file land-pr scripts/pr-push-and-create.sh \
  "no bare git push (Issue #188)" \
  '^[[:space:]]*git push[[:space:]]*$|^[[:space:]]*if ! git push[[:space:]]*>'
# Companion: post-push verification via ls-remote must be present.
check_in_file land-pr scripts/pr-push-and-create.sh \
  "post-push verification via ls-remote (Issue #188)" \
  'git ls-remote origin'

# --- BRANCH_SLUG derivation (foundation bug fix from Phase 1A) ---
check_fixed land-pr "BRANCH_SLUG derivation"  'BRANCH_SLUG'

# --- PR #131 past-failure preamble (issue #133; WI 3.4 RELOCATED from /commit) ---
# Spec verbatim (WI 3.4): the regex MUST anchor on the substantive failure
# wording so paraphrase drift trips the assertion.
check land-pr "PR #131 past-failure preamble" 'Past failure.*PR #131|skipped Step 6 on PR #131'

# --- Caller loop: allow-list parser pattern ---
# Issue #576: per-key assertions over the FULL canonical key set so a
# silent drop of any sidecar key (REBASE_STDERR_FILE per #535,
# CONFLICT_FILES_LIST, CALL_ERROR_FILE) trips conformance. The legacy
# 3-key alternation pattern only required STATUS|PR_URL|PR_NUMBER to
# appear anywhere — sidecar key regressions were invisible. Canonical
# list is defined by skills/land-pr/references/caller-loop-pattern.md
# `case "$KEY" in ...` arms.
for _LP_KEY in STATUS PR_URL PR_NUMBER PR_EXISTING CI_STATUS CI_LOG_FILE \
               MERGE_REQUESTED MERGE_REASON PR_STATE REASON \
               CONFLICT_FILES_LIST CALL_ERROR_FILE REBASE_STDERR_FILE; do
  # Word-anchor (\b) so a rename like REBASE_STDERR_FILE_RENAMED can't
  # spuriously satisfy the assertion via substring match.
  check land-pr "allow-list parser key: $_LP_KEY" "\\b${_LP_KEY}\\b"
done

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
# Issue #576: per-key assertion over the FULL canonical key set against
# the canonical reference itself. If anyone edits caller-loop-pattern.md
# and drops a sidecar key from the case-arm, the reference would drift
# from the 5 caller copies — this fails-closed at the source-of-truth.
for _LP_KEY in STATUS PR_URL PR_NUMBER PR_EXISTING CI_STATUS CI_LOG_FILE \
               MERGE_REQUESTED MERGE_REASON PR_STATE REASON \
               CONFLICT_FILES_LIST CALL_ERROR_FILE REBASE_STDERR_FILE; do
  # Word-anchor (\b) so a rename can't spuriously satisfy via substring.
  check_in_file land-pr references/caller-loop-pattern.md \
    "caller loop allow-list key: $_LP_KEY" "\\b${_LP_KEY}\\b"
done
# Defense-in-depth: caller pattern must explicitly forbid `source` of the
# result file. Two literal landmarks (defense + parser-rationale section).
check_fixed land-pr 'never source: contract bullet'   'Never `source`'
check_fixed land-pr 'never source: parser rationale'  'allow-list parser, not `source`'

# --- Caller pattern: no source-based result parsing ---
check_not land-pr "no source-based result parsing in caller pattern" \
  'source[[:space:]]+.*RESULT_FILE|^\.[[:space:]]+.*RESULT_FILE'

# --- Caller STATUS case-arm coverage (Issue #624) ---
# /land-pr documents 12 STATUS values in its return envelope
# (skills/land-pr/SKILL.md:158). The 4 caller skills + the canonical
# reference pattern must enumerate every documented value as an explicit
# case-arm — silent fall-through (e.g. `auto-rebase-blocked` reaching the
# CI-status check below and being coerced to `pr-ready`) is a real-life
# hazard (see issue body's "auto-rebase-blocked path is hit in real life"
# section). Pin shape mirrors #602's case-arm-per-status closure but on
# /land-pr's STATUS vocabulary instead of `.landed`. The `*)` default arm
# is also required so unknown future STATUS values fail LOUD.
_LP_STATUS_VALUES="created monitored merged push-failed rebase-conflict create-failed monitor-failed merge-failed rebase-failed behind-thrash auto-rebase-conflict auto-rebase-blocked"
# Per-caller assertion: each STATUS appears at line-leading (after
# whitespace) OR after `|` followed by `)` or `|`. This anchors on the
# case-arm syntax so a mere mention in a comment does NOT satisfy.
# Each entry is "skill_name relpath".
for _LP_PAIR in \
    "commit modes/pr.md" \
    "do modes/pr.md" \
    "fix-issues modes/pr.md" \
    "run-plan modes/pr.md" \
    "land-pr references/caller-loop-pattern.md"; do
  _LP_SKILL="${_LP_PAIR%% *}"
  _LP_REL="${_LP_PAIR#* }"
  for _LP_STATUS in $_LP_STATUS_VALUES; do
    # Match the STATUS as a case-arm token: preceded by line-start
    # whitespace OR `|`, followed by `)` or `|`. The `[[:space:]]*\|` form
    # also covers the alternation form `STATUS_A|STATUS_B)`.
    check_in_file "$_LP_SKILL" "$_LP_REL" \
      "STATUS case-arm: $_LP_STATUS (Issue #624)" \
      "(^[[:space:]]+|\\|)${_LP_STATUS}(\\)|\\|)"
  done
  # The `*)` default arm is mandatory — surfaces unknown future STATUS
  # values via `LAND_OUTCOME="unknown-status-..."` + stderr WARN (or
  # bare stderr WARN in /run-plan which doesn't carry LAND_OUTCOME).
  check_in_file "$_LP_SKILL" "$_LP_REL" \
    "STATUS case-arm: default arm \`*)\` (Issue #624)" \
    'unrecognized /land-pr STATUS'
done

# --- Step 7b post-merge fast-forward (Issue #254) ---
# Guard the literal sentinel so a future refactor can't silently drop the
# step that fast-forwards local main after a successful squash-merge.
# Without this step, downstream skills (worktree creation, status checks)
# anchor on stale main and orchestrators improvise destructive fixes.
check_fixed land-pr "Step 7b post-merge fast-forward sentinel" \
  'Step 7b — Fast-forward local main'

# --- Step 7d terminal-wait + Step 6b UNKNOWN resolver (Issue #871) ---
# Guard the two coverage-gap closures so a refactor can't silently drop
# them: (1) Step 6b must resolve a transient UNKNOWN before the BEHIND loop
# so the rebase fires; (2) Step 7d must drive a queued auto-merge to a
# terminal state instead of returning while the PR is still OPEN/BEHIND.
check_fixed land-pr "Step 7d terminal-wait sentinel (Issue #871)" \
  'Step 7d — Drive a queued auto-merge to a terminal state'
check_fixed land-pr "Step 7d bounded wait reason token (Issue #871)" \
  'auto-merge-wait-timeout'
check_fixed land-pr "Step 6b UNKNOWN resolver before BEHIND loop (Issue #871)" \
  'UNKNOWN_POLL_MAX'

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
# Issue #505 — block-bad-cron.sh (#456) and block-main-edits.sh (#308) were
# wired into .claude/settings.json but missing from SKILL.md install bullets
# AND canonical-triples table; fresh installs silently lacked both hooks.
check_fixed update-zskills "Step C triples: PreToolUse CronCreate block-bad-cron (#505)" \
  'PreToolUse   | CronCreate | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-bad-cron.sh"`'
check_fixed update-zskills "Step C triples: PreToolUse Edit|Write block-main-edits (#505)" \
  'PreToolUse   | Edit\|Write | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-main-edits.sh"`'
# Install-bullet copies must also enumerate both hooks (Step C copy loop).
check_fixed update-zskills "Step C install bullet: block-bad-cron.sh (#505)" \
  'For `block-bad-cron.sh`: copy as-is from `$PORTABLE/hooks/` to'
check_fixed update-zskills "Step C install bullet: block-main-edits.sh (#505)" \
  'For `block-main-edits.sh`: copy as-is from `$PORTABLE/hooks/` to'

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

# Issue #655 — every hooks/block-*.sh must be referenced in /update-zskills's
# install list (Step C copy-list prose AND/OR the canonical-triples table).
# Closes the install-list-omission family (instance 1: #505 missed
# block-bad-cron.sh + block-main-edits.sh; instance 2: #655 missed
# block-run-plan-unclaimed.sh). Any new hook landing in hooks/block-*.sh
# without a corresponding /update-zskills install-list reference fails CI.
for hook_path in "$REPO_ROOT"/hooks/block-*.sh; do
  hook_basename=$(basename "$hook_path")
  if grep -qF -- "$hook_basename" "$REPO_ROOT/skills/update-zskills/SKILL.md"; then
    pass "[update-zskills] #655: install-list references $hook_basename"
  else
    fail "[update-zskills] #655: hook $hook_basename not in /update-zskills install list" \
      "missing from skills/update-zskills/SKILL.md (Step C copy list and/or canonical-triples table)"
  fi
done

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
echo "=== /draft-tests — structural existence pins (issue #861) ==="
# PR #855 split /draft-tests's SKILL.md into 5 files (3 modes + 2 references).
# This block asserts every split file exists on BOTH the source tree
# (skills/draft-tests/) AND the install mirror (.claude/skills/draft-tests/),
# failing closed if any vanishes. The /draft-tests row in
# docs/issues/ISSUES_PLAN.md noted that prior coverage
# (test-skill-conformance.sh:936 /land-pr caller array + variable-family
# allowlist in test-skill-invariants.sh) is sideways — it gates downstream
# behavior but never asserts the files themselves. This block closes that
# gap.
DT_REQ_FILES=(
  "skills/draft-tests/modes/draft.md"
  "skills/draft-tests/modes/backfill.md"
  "skills/draft-tests/modes/land.md"
  "skills/draft-tests/references/test-spec-format.md"
  "skills/draft-tests/references/design-constraints.md"
  ".claude/skills/draft-tests/modes/draft.md"
  ".claude/skills/draft-tests/modes/backfill.md"
  ".claude/skills/draft-tests/modes/land.md"
  ".claude/skills/draft-tests/references/test-spec-format.md"
  ".claude/skills/draft-tests/references/design-constraints.md"
)
for dt_path in "${DT_REQ_FILES[@]}"; do
  if [ -f "$REPO_ROOT/$dt_path" ]; then
    pass "[draft-tests-presence] $dt_path exists"
  else
    fail "[draft-tests-presence] $dt_path exists" "$dt_path"
  fi
done

echo ""
echo "=== /draft-tests — behavior contracts (WI 6.3) ==="
# Anchor: tests/test-skill-conformance.sh draft-tests block — one check
# per WI 6.3 sub-bullet of plans/DRAFT_TESTS_SKILL_PLAN.md (current count:
# 11). When WI 6.3 grows or shrinks, add or remove a single check line
# here in tandem; AC-6.2 is a list-membership invariant, not a literal
# count. WI 6.3 is the authoritative enumeration source.
#
# 1. Frontmatter shape (incl. `[<guidance>]` positional tail in argument-hint)
check       draft-tests "frontmatter argument-hint with [auto] [<guidance>]" \
  '^argument-hint:[[:space:]]+"<plan-file> \[rounds N\] \[auto\] \[<guidance>\]"'
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
echo "=== /plans render-index.py — issue #215 ==="
# /plans rebuild MUST shell out to render-index.py for markdown emission
# (no prose-driven rendering loop). Past failure: PR #214's prose-driven
# rebuild misclassified 5 canaries as Complete because the precedence
# rule was buried in a parenthetical inside a prose table.
check_executable plans scripts/render-index.py "render-index.py exists and is executable"
check_in_file plans SKILL.md "Mode: Rebuild references render-index.py" 'render-index\.py'

echo ""
echo "=== /draft-plan & /research-and-plan — no PLAN_INDEX writes (issue #216) ==="
# Both skills MUST NOT mutate PLAN_INDEX.md — it's a render of
# source-of-truth (collect.py output) and is regenerated by
# /plans rebuild or auto-refreshed by /plans Mode: Show staleness check.
# The prose-driven incremental writes were the same bug class as #215.
check_not draft-plan        "no PLAN_INDEX.md write instruction" \
    'add a row to.*"?Ready to Run"?|append.*to PLAN_INDEX'
check_not research-and-plan "no PLAN_INDEX.md write instruction" \
    'add a row to.*"?Ready to Run"?|append.*to PLAN_INDEX|Update.*PLAN_INDEX\.md.*if it exists'

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
echo "=== ensure-worktree preamble adoption ==="
# Phase 5 (PREAMBLE_WORKTREE_GATE): every adopter skill MUST embed the
# `bash "$HELPER"` invocation form of the shared ensure-worktree.sh
# preamble. The preamble defines:
#   HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/ensure-worktree.sh"
# and dispatches via `WT_PATH=$(bash "$HELPER" \ ...)`. A fixed-string
# match on `bash "$HELPER"` is the load-bearing literal — if the slug
# routing in any adopter regresses (e.g. someone open-codes
# create-worktree.sh again), this assertion catches it.
check_fixed draft-plan                "ensure-worktree invocation" 'bash "$HELPER"'
check_fixed refine-plan               "ensure-worktree invocation" 'bash "$HELPER"'
check_fixed draft-tests               "ensure-worktree invocation" 'bash "$HELPER"'
check_fixed block-diagram/add-block   "ensure-worktree invocation" 'bash "$HELPER"'
check_fixed block-diagram/add-example "ensure-worktree invocation" 'bash "$HELPER"'
check_fixed fix-issues                "ensure-worktree invocation" 'bash "$HELPER"'

echo ""
echo "=== clear-tracking recovery hint — dual-lane path (#865) ==="
# User-facing tracking-cleanup recovery hints must NOT print a bare
# mirror-only clear-tracking.sh path as the SOLE hint: on the plugin lane
# there is no .claude/skills/ mirror, so the legacy path does not exist.
# Each site that mentions clear-tracking.sh MUST also carry the
# ${CLAUDE_PLUGIN_ROOT}-resolved form. A future edit that drops the
# plugin-lane path (regressing to bare mirror-only) fails closed here.
CLEAR_TRACKING_HINT_SITES=(
  "skills/research-and-go/SKILL.md"
  "skills/run-plan/modes/execute-phase.md"
  "skills/run-plan/SKILL.md"
)
CT_HINT_CHECKED=0
for rel in "${CLEAR_TRACKING_HINT_SITES[@]}"; do
  f="$REPO_ROOT/$rel"
  [ -f "$f" ] || continue
  # Only enforce on files that actually reference clear-tracking.sh.
  if grep -q 'clear-tracking\.sh' "$f"; then
    CT_HINT_CHECKED=$((CT_HINT_CHECKED + 1))
    if grep -qF '${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/clear-tracking.sh' "$f"; then
      pass "[$rel] clear-tracking.sh hint carries \${CLAUDE_PLUGIN_ROOT} (plugin-lane) path"
    else
      fail "[$rel] clear-tracking.sh hint missing plugin-lane path" '${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/clear-tracking.sh (bare mirror-only path is wrong on the plugin lane — #865)'
    fi
  fi
done
# Guard against the site list silently going stale (files renamed away or
# clear-tracking.sh dropped everywhere) making the assertion vacuous.
if [ "$CT_HINT_CHECKED" -lt 2 ]; then
  fail "[clear-tracking dual-lane] too few sites scanned ($CT_HINT_CHECKED < 2)" "clear-tracking.sh recovery-hint sites moved/removed — update CLEAR_TRACKING_HINT_SITES (#865)"
else
  pass "clear-tracking.sh recovery-hint dual-lane scan covered $CT_HINT_CHECKED sites"
fi

echo ""
echo "=== ensure-worktree.sh caller contract ==="
# Companion to the create-worktree.sh caller-contract scan above.
# Every multi-line `bash "$HELPER" \` invocation in skills/ AND
# block-diagram/ (the preamble HELPER literal form — see "ensure-worktree
# preamble adoption" above) must include `--pipeline-id` within the next
# 12 lines. The block-diagram/ subtree is scanned here (but NOT in the
# create-worktree.sh scan above — post-Phase-3 /add-block has 0
# create-worktree.sh calls so extending that scan adds no value, DA-12).
#
# Floor: ≥6 callers (one per adopter: draft-plan, refine-plan,
# draft-tests, block-diagram/add-block, block-diagram/add-example,
# fix-issues). If the regex breaks and matches fewer, fail loudly
# rather than vacuously pass.
EW_PIPELINE_ID_CONTRACT_FAIL=0
EW_PIPELINE_ID_CONTRACT_CALLS=0
while IFS=: read -r file lineno _; do
  [ -z "$file" ] && continue
  EW_PIPELINE_ID_CONTRACT_CALLS=$((EW_PIPELINE_ID_CONTRACT_CALLS + 1))
  # Look at lines $lineno through $lineno+12 in $file.
  slice=$(sed -n "${lineno},$((lineno + 12))p" "$file" 2>/dev/null)
  if ! echo "$slice" | grep -q -- '--pipeline-id'; then
    fail "ensure-worktree caller missing --pipeline-id" "$file:$lineno"
    EW_PIPELINE_ID_CONTRACT_FAIL=$((EW_PIPELINE_ID_CONTRACT_FAIL + 1))
  fi
done < <(grep -rn --include='*.md' -E 'bash[[:space:]]+"\$HELPER".*\\$' "$REPO_ROOT/skills/" "$REPO_ROOT/block-diagram/")
if [ "$EW_PIPELINE_ID_CONTRACT_CALLS" -lt 6 ]; then
  fail "ensure-worktree caller scan found too few invocations (${EW_PIPELINE_ID_CONTRACT_CALLS} < 6) — pattern broken?" "grep regex drift"
  EW_PIPELINE_ID_CONTRACT_FAIL=$((EW_PIPELINE_ID_CONTRACT_FAIL + 1))
fi
if [ "$EW_PIPELINE_ID_CONTRACT_FAIL" -eq 0 ]; then
  pass "every ensure-worktree.sh invocation in skills/+block-diagram/ passes --pipeline-id (scanned ${EW_PIPELINE_ID_CONTRACT_CALLS})"
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
# skills/run-plan/modes/execute-phase.md, where bash fences live inside a
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

  # The .md deny-list scan itself lives in the SHARED script
  # tests/lib/forbidden-literals-scan.sh (#948) so the single-source-of-
  # truth guarantee is STRUCTURAL: tests/test-hooks.sh's fixture-extension
  # Surface 2 probe calls the SAME script directly against a synthetic
  # tree, instead of nesting this whole suite. The scan's matching
  # semantics, output (DRIFT lines), and gate behavior are unchanged — it
  # still walks the real skills/ + block-diagram/ trees and fails on any
  # forbidden literal. (The FIXED_LITERALS / REGEX_PATTERNS arrays parsed
  # above remain in scope for the extended-scope sibling scan further down.)
  # shellcheck source=tests/lib/forbidden-literals-scan.sh
  . "$SCRIPT_DIR/lib/forbidden-literals-scan.sh"
  DRIFT_HITS_OUT="$(run_forbidden_literals_scan "$REPO_ROOT" "$FORBIDDEN_FIXTURE")"
  DRIFT_FAIL=$?

  if [ "$DRIFT_FAIL" -eq 0 ]; then
    pass "no skill-file drift hardcodes (deny-list clean against tests/fixtures/forbidden-literals.txt)"
  else
    DRIFT_HIT_COUNT=$(printf '%s' "$DRIFT_HITS_OUT" | grep -c .)
    fail "skill-file drift hardcodes detected" "$DRIFT_HIT_COUNT hit(s)"
    printf '%s\n' "$DRIFT_HITS_OUT" | while IFS= read -r h; do
      [ -n "$h" ] && printf '    %s\n' "$h" >&2
    done
  fi

  # Regression fixture (#458): the three deny-list/positive-side/coverage
  # scanner roots MUST cover both skills/ AND block-diagram/. Without this,
  # the #454 sweep's regression mode (re-injecting TZ=America/New_York or
  # `npm run test:all` into a block-diagram SKILL.md) silently passes
  # conformance. Inspect the live scanner source for the dual-root find
  # invocation. Fails closed if a future edit drops `block-diagram` from
  # any of the three sites.
  #
  # As of #948 the .md deny-list scan's dual-root find lives in the shared
  # script tests/lib/forbidden-literals-scan.sh (it scans $scan_root/skills
  # + $scan_root/block-diagram), NOT inline in this suite. Count both files
  # so the #458 guarantee survives the relocation.
  SELF="$REPO_ROOT/tests/test-skill-conformance.sh"
  SCAN_LIB="$REPO_ROOT/tests/lib/forbidden-literals-scan.sh"
  # Prose-imperative coverage scan (still inline) + extended-scope are in $SELF.
  bd_root_hits=$(grep -cE 'find "\$REPO_ROOT/skills" "\$REPO_ROOT/block-diagram"' "$SELF" 2>/dev/null || echo 0)
  # The deny-list scan's dual-root find now lives in the shared script,
  # parameterised on $scan_root.
  bd_lib_hits=$(grep -cE 'find "\$scan_root/skills" "\$scan_root/block-diagram"' "$SCAN_LIB" 2>/dev/null || echo 0)
  # Also count the positive-side scanner's `extra_root` plumbing (a 4th-arg
  # variant that passes the second root through the helper function).
  bd_extra_root_hits=$(grep -cE 'scan_positive_side "\$REPO_ROOT/skills".*"\$REPO_ROOT/block-diagram"' "$SELF" 2>/dev/null || echo 0)
  # Expected: 1 dual-root find in the shared deny-list script + 1 dual-root
  # find inline for prose-imperative coverage + 1 scan_positive_side with
  # extra_root (real-tree case). Total >= 3 references to block-diagram
  # across the three scanner-root sites.
  bd_total=$((bd_root_hits + bd_lib_hits + bd_extra_root_hits))
  if [ "$bd_total" -ge 3 ]; then
    pass "deny-list/positive-side/coverage scanners all scope block-diagram/ (#458 regression fixture: found $bd_total of 3 expected block-diagram scan-root references)"
  else
    fail "deny-list scanner scope regression" "expected 3 block-diagram scan-root references (1 dual-root find in $SCAN_LIB + 1 dual-root find + 1 scan_positive_side extra_root in $SELF), got $bd_total — at least one of the three scanner roots has regressed to skills/-only (#458)"
  fi
fi

echo ""
echo "=== Inline-prose resolve-via uses lane-portable wording (#832/#833) ==="
# Fence-aware gate: the legacy single-lane literal
#   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
# is PERMANENTLY valid inside ```fenced``` bash blocks (decision D23 /
# finding F-DA2-4 — it is the legacy /update-zskills-lane source form and the
# `else` fallback branch of the dual-lane prelude). What is NOT valid is an
# INLINE-PROSE reference to it — a single-backtick code-span on a non-fenced
# line, typically a `(resolve via `...`)` parenthetical. A mirror-less plugin
# consumer (the primary plugin install — no `.claude/skills/` mirror) that
# follows that prose runs a path that does not exist. Such prose MUST instead
# point at the lane-portable dual-lane prelude in
# references/canonical-config-prelude.md §1.
#
# Fence-awareness is implemented in PYTHON (repo convention — no jq): walk each
# skills/**/*.md + block-diagram/**/*.md, toggle fenced-block state on ```/~~~
# fence-openers, and flag the literal ONLY when it appears inside an inline
# code-span (`...`) on a NON-fenced line. The `else` fallback line inside the
# dual-lane prelude lives in a bash fence and is therefore NEVER flagged. An
# <!-- allow-hardcoded: ... reason: ... --> marker on the line immediately
# above the prose line exempts that line (same marker convention as the
# deny-list scan above).
PROSE_RESOLVE_FAIL=0
PROSE_RESOLVE_HITS="$(ZS_REPO_ROOT="$REPO_ROOT" "${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}" <<'PYEOF'
import os, sys
repo = os.environ["ZS_REPO_ROOT"]
LIT = '. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"'
INLINE = "`" + LIT + "`"          # the literal wrapped in a single-backtick code-span
MARKER_FRAG = "allow-hardcoded:"  # an allow-hardcoded marker (verbatim or naming this literal) exempts the next prose line
roots = [os.path.join(repo, "skills"), os.path.join(repo, "block-diagram")]
files = []
for root in roots:
    for dirpath, _dirs, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(".md"):
                files.append(os.path.join(dirpath, fn))
hits = []
for f in sorted(files):
    in_fence = False
    prev = ""
    with open(f, encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            stripped = line.lstrip()
            if stripped.startswith("```") or stripped.startswith("~~~"):
                in_fence = not in_fence
                prev = line
                continue
            if not in_fence and INLINE in line:
                if MARKER_FRAG not in prev:
                    rel = os.path.relpath(f, repo)
                    hits.append("%s:%d: inline-prose `resolve via ...zskills-resolve-config.sh` code-span "
                                "is single-lane only — replace with a reference to the dual-lane prelude in "
                                "references/canonical-config-prelude.md \xc2\xa71 (or add an allow-hardcoded "
                                "marker on the line above)." % (rel, i))
            prev = line
for h in hits:
    print(h)
sys.exit(0)
PYEOF
)"
if [ -n "$PROSE_RESOLVE_HITS" ]; then
  PROSE_RESOLVE_FAIL=1
  fail "inline-prose resolve-via uses single-lane literal (#832/#833)" "$(printf '%s' "$PROSE_RESOLVE_HITS" | grep -c .) hit(s)"
  printf '%s\n' "$PROSE_RESOLVE_HITS" | while IFS= read -r h; do
    [ -n "$h" ] && printf '    %s\n' "$h" >&2
  done
else
  pass "no inline-prose single-lane resolve-via references (lane-portable wording per #832/#833)"
fi

echo ""
echo "=== Tracking-fence empty-PIPELINE_ID guard (#852) ==="
# A tracking-marker fence that does `mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"`
# (or, more generally, writes under .zskills/tracking/$PIPELINE_ID) must be
# preceded by a fail-loud guard:
#
#   [ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID ..." >&2; exit 1; }
#
# Without it, an upstream hiccup that empties $PIPELINE_ID (e.g. a failed
# resolver source line leaving $ZSKILLS_SKILLS_ROOT unset, so the
# sanitize-pipeline-id.sh cmd-substitution yields "") produces a SILENT flat
# write to `.zskills/tracking//...` — violating the per-pipeline-subdir
# invariant and tripping the dedup hook on later runs. This tripwire asserts
# the guard appears within the preceding 10 lines of the SAME bash fence as
# every `mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"` line.
TRACK_GUARD_FAIL=0
TRACK_GUARD_HITS="$(ZS_REPO_ROOT="$REPO_ROOT" "${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}" <<'PYEOF'
import os, re, sys
repo = os.environ["ZS_REPO_ROOT"]
roots = [os.path.join(repo, "skills"), os.path.join(repo, "block-diagram")]
files = []
for root in roots:
    for dirpath, _dirs, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(".md"):
                files.append(os.path.join(dirpath, fn))
MKDIR = re.compile(r'mkdir -p "\$MAIN_ROOT/\.zskills/tracking/\$PIPELINE_ID"')
GUARD = re.compile(r'\[ -n "\$PIPELINE_ID" \]')
WINDOW = 10
hits = []
for f in sorted(files):
    with open(f, encoding="utf-8") as fh:
        lines = fh.readlines()
    # Build a per-line fence id (None outside any fence).
    in_fence = False
    fence_id = 0
    fence_of = [None] * (len(lines) + 1)  # 1-indexed
    for i, line in enumerate(lines, 1):
        s = line.lstrip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            if in_fence:
                fence_id += 1
            continue
        fence_of[i] = fence_id if in_fence else None
    for i, line in enumerate(lines, 1):
        if fence_of[i] is None or not MKDIR.search(line):
            continue
        fid = fence_of[i]
        guarded = False
        for j in range(i - 1, max(0, i - 1 - WINDOW), -1):
            if fence_of[j] != fid:
                continue  # left the fence — keep scanning back within window
            if GUARD.search(lines[j - 1]):
                guarded = True
                break
        if not guarded:
            rel = os.path.relpath(f, repo)
            hits.append('%s:%d: tracking mkdir under $PIPELINE_ID with no '
                        '`[ -n "$PIPELINE_ID" ]` guard within the preceding %d '
                        'lines of the same fence (#852 — would silently flat-write '
                        'on empty $PIPELINE_ID).' % (rel, i, WINDOW))
for h in hits:
    print(h)
sys.exit(0)
PYEOF
)"
if [ -n "$TRACK_GUARD_HITS" ]; then
  TRACK_GUARD_FAIL=1
  fail "tracking fence missing empty-PIPELINE_ID guard (#852)" "$(printf '%s' "$TRACK_GUARD_HITS" | grep -c .) hit(s)"
  printf '%s\n' "$TRACK_GUARD_HITS" | while IFS= read -r h; do
    [ -n "$h" ] && printf '    %s\n' "$h" >&2
  done
else
  pass "all tracking mkdir fences carry an empty-PIPELINE_ID fail-loud guard (#852)"
fi

echo ""
echo "=== No executable bare python3 in skill fenced-bash (#1083) ==="
# Every EXECUTABLE bare `python3` invocation in a consumer skill fenced-bash
# block hits the broken Microsoft Store App-Execution-Alias stub on Windows
# (same root cause as #1075). Skills must resolve $PYTHON via the config prelude
# (skills/update-zskills/scripts/zskills-resolve-config.sh exports it) and call
# `"$PYTHON" …` instead. This tripwire fails closed on any new executable bare
# `python3` in a skill .md fenced-bash block, so the Windows regression can't
# creep back in.
#
# Fence-aware (PYTHON, repo convention — no jq): walk skills/**/*.md +
# block-diagram/**/*.md, toggle fenced-block state on ```/~~~ openers, and flag
# ONLY lines INSIDE a fence where `python3` appears at a COMMAND POSITION
# (line-start after optional whitespace, or immediately after a shell
# command-separator: | ( { ; & or a $( / <( command-substitution opener)
# followed by an executable form: -c / -m / - (stdin) / "$ (quoted path) /
# ' (quoted -c body) / a path or module token.
#
# EXEMPT (NOT flagged):
#   - prose lines OUTSIDE any fence (a `python3` mention in prose / inline code)
#   - `#!/usr/bin/env python3` shebangs
#   - lines already using "$PYTHON" / zskills_resolve_python / command -v python3
#   - echo/printf STRING mentions like `echo "ERROR: python3 -m … failed"`
#     (python3 is NOT at a command position there — it's mid-string)
#   - a line carrying (or immediately preceded by) an `allow-hardcoded` marker
PY3_FENCE_FAIL=0
PY3_FENCE_HITS="$(ZS_REPO_ROOT="$REPO_ROOT" "${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}" <<'PYEOF'
import os, re, sys
repo = os.environ["ZS_REPO_ROOT"]
roots = [os.path.join(repo, "skills"), os.path.join(repo, "block-diagram")]
files = []
for root in roots:
    for dirpath, _dirs, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(".md"):
                files.append(os.path.join(dirpath, fn))

# python3 at a command position, in an executable form.
#   (^|[|(){};&]|\$\(|<\()  — start-of-(stripped)-line OR a command separator /
#                             command-substitution opener immediately before
#   \s*                     — optional whitespace
#   python3\b               — the bare interpreter
#   \s+(-c|-m|-\s|["'/]|...) — an executable continuation (flag, stdin '-',
#                             quoted/absolute path, or a module/script token)
CMDPOS = re.compile(
    r'(?:^|[|(){};&]|\$\(|<\()\s*python3\b\s+'
    r'(?:-c\b|-m\b|-\s|["\']|/|[A-Za-z0-9_.]+)'
)
MARKER_FRAG = "allow-hardcoded:"

hits = []
for f in sorted(files):
    with open(f, encoding="utf-8") as fh:
        lines = fh.readlines()
    in_fence = False
    prev = ""
    for i, line in enumerate(lines, 1):
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            prev = line
            continue
        if not in_fence:
            prev = line
            continue
        # shebangs are not executable invocations of a bare python3 on PATH
        if stripped.startswith("#!"):
            prev = line
            continue
        # allow-hardcoded exemption (this line or the line immediately above)
        if MARKER_FRAG in line or MARKER_FRAG in prev:
            prev = line
            continue
        m = CMDPOS.search(stripped)
        if m:
            # Defensive: if the match's python3 is actually part of "$PYTHON"
            # or command -v python3, the regex above already won't match
            # (different surrounding text), so a hit here is a real one.
            rel = os.path.relpath(f, repo)
            hits.append('%s:%d: executable bare `python3` in fenced bash — '
                        'resolve $PYTHON via the config prelude and use '
                        '`"$PYTHON" …` instead (#1083). Line: %s'
                        % (rel, i, stripped.rstrip()))
        prev = line
for h in hits:
    print(h)
sys.exit(0)
PYEOF
)"
if [ -n "$PY3_FENCE_HITS" ]; then
  PY3_FENCE_FAIL=1
  fail "executable bare python3 in skill fenced-bash (#1083)" "$(printf '%s' "$PY3_FENCE_HITS" | grep -c .) hit(s)"
  printf '%s\n' "$PY3_FENCE_HITS" | while IFS= read -r h; do
    [ -n "$h" ] && printf '    %s\n' "$h" >&2
  done
else
  pass "no executable bare python3 in skill fenced-bash (all resolve \$PYTHON — #1083)"
fi

echo ""
echo "=== Fresh-config scaffold: both lanes seed output.{plans,issues,reports}_dir = docs/ ==="
# A FRESH config scaffold must default the output path keys to the documented
# docs/ layout so a brand-new consumer's dashboard + plan-skills find plans in
# docs/plans out of the box (resolver falls back to legacy plans/ only when the
# output block is ABSENT — proven separately in tests/test-zskills-paths.sh
# Case 1). Both scaffold sites must write the SAME output block:
#   - plugin lane: hooks/session-start-materialise.sh seed dict
#   - /update-zskills lane: skills/update-zskills/SKILL.md install scaffold JSON
# This tightens the prior invariant (the seed used to carry NO output block).
SCAFFOLD_PY="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
SCAFFOLD_HITS="$(ZS_REPO_ROOT="$REPO_ROOT" "$SCAFFOLD_PY" <<'PYEOF'
import json, os, re, sys

repo = os.environ["ZS_REPO_ROOT"]
errs = []

# --- (1) Plugin-lane seed: extract the `cfg = { ... }` dict literal from the
#     materialiser and eval it as Python (it's a plain dict of literals; the
#     only non-literal is os.environ["PROJECT_NAME"], which we stub).
mat = os.path.join(repo, "hooks", "session-start-materialise.sh")
src = open(mat, encoding="utf-8").read()
m = re.search(r"\ncfg = (\{.*?\n\})\n", src, re.DOTALL)
plugin_out = None
if not m:
    errs.append("could not locate `cfg = {...}` dict in session-start-materialise.sh")
else:
    ns = {"os": type("O", (), {"environ": {"PROJECT_NAME": "x"}})()}
    try:
        cfg = eval(m.group(1), {"__builtins__": {}, "True": True, "False": False}, ns)
        plugin_out = cfg.get("output")
    except Exception as e:  # noqa: BLE001
        errs.append("failed to eval plugin seed cfg dict: %r" % (e,))

# --- (2) /update-zskills lane: extract the install scaffold JSON block under
#     the "Content to write to `.claude/zskills-config.json`:" heading, strip
#     the <detected>/<preset.*> placeholders to JSON-valid dummies, json.load.
skill = os.path.join(repo, "skills", "update-zskills", "SKILL.md")
sk = open(skill, encoding="utf-8").read()
idx = sk.find("Content to write to `.claude/zskills-config.json`:")
scaffold_out = None
if idx < 0:
    errs.append("could not locate install scaffold heading in update-zskills/SKILL.md")
else:
    fence = re.search(r"```json\n(.*?)\n[ \t]*```", sk[idx:], re.DOTALL)
    if not fence:
        errs.append("could not locate ```json scaffold fence in update-zskills/SKILL.md")
    else:
        raw = fence.group(1)
        # Replace placeholder tokens with JSON-valid dummies.
        raw = raw.replace("<preset.main_protected>", "true")
        raw = re.sub(r'"<[^"]*>"', '"x"', raw)   # quoted <detected>/<preset.landing>
        raw = re.sub(r'\["<[^"]*>"\]', '["x"]', raw)  # ["<detected>"] arrays
        try:
            scaffold_out = json.loads(raw).get("output")
        except Exception as e:  # noqa: BLE001
            errs.append("install scaffold JSON does not parse after placeholder strip: %r" % (e,))

EXPECTED = {"plans_dir": "docs/plans", "issues_dir": "docs/issues", "reports_dir": "docs/reports"}
if plugin_out != EXPECTED:
    errs.append("plugin seed output block != %r (got %r)" % (EXPECTED, plugin_out))
if scaffold_out != EXPECTED:
    errs.append("install scaffold output block != %r (got %r)" % (EXPECTED, scaffold_out))
if plugin_out is not None and scaffold_out is not None and plugin_out != scaffold_out:
    errs.append("the two seeds DISAGREE on the output block: plugin=%r scaffold=%r"
                % (plugin_out, scaffold_out))

for e in errs:
    print(e)
sys.exit(0)
PYEOF
)"
if [ -z "$SCAFFOLD_HITS" ]; then
  pass "fresh-config scaffold: both lanes seed identical output = docs/{plans,issues,reports}"
else
  fail "fresh-config scaffold output block (both-lanes symmetry)" "$SCAFFOLD_HITS"
  printf '%s\n' "$SCAFFOLD_HITS" | while IFS= read -r h; do
    [ -n "$h" ] && printf '    %s\n' "$h" >&2
  done
fi

echo ""
echo "=== No skill-file drift hardcodes (extended scope: hooks/, scripts/, *.py) ==="
# Sibling deny-list scan over non-markdown sources that the existing
# skills/**/*.md scanner above doesn't see:
#
#   - hooks/*.sh, hooks/*.sh.template       (hook source)
#   - scripts/*.sh                          (release tooling + skill-version stage check)
#   - skills/**/scripts/*.py                (Python helpers under skills)
#   - block-diagram/**/scripts/*.py         (Python helpers under block-diagram add-on skills)
#
# Same forbidden-literals fixture as the .md scanner. Allowlist marker
# uses a bash/Python `#` comment instead of HTML:
#
#   # allow-hardcoded: <literal> reason: <why>
#
# The marker may appear on the same line as the hit (suffix comment) OR
# on the immediately-preceding line. Markers stack (consecutive marker
# lines exempt multiple literals for the line directly below).
#
# Regex entries (`re:` prefix in the fixture) are matched on the line as
# extended regex; the corresponding allow-hardcoded marker names the
# pattern WITHOUT the `re:` prefix (same rule as the .md scanner).

if [ -r "$FORBIDDEN_FIXTURE" ]; then
  EXT_DRIFT_FAIL=0
  EXT_DRIFT_HITS=()

  # Build the file list. Use find with -path -prune to avoid scanning
  # vendored or generated paths. The .claude/ mirror is intentionally
  # skipped: bytes are guaranteed identical to the source by mirror-parity
  # tests, and double-scanning would just produce paired DRIFT messages.
  EXT_FILES=()
  while IFS= read -r f; do
    EXT_FILES+=("$f")
  done < <(
    {
      find "$REPO_ROOT/hooks" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.sh.template' \) 2>/dev/null
      find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
      find "$REPO_ROOT/skills" -type f -path '*/scripts/*.py' 2>/dev/null
      find "$REPO_ROOT/block-diagram" -type f -path '*/scripts/*.py' 2>/dev/null
    } | sort
  )

  for src_file in "${EXT_FILES[@]}"; do
    # Two-line lookback for the allow-hardcoded marker (preceding-line OR
    # same-line). Implement via a sliding prev_line buffer.
    prev_line=""
    line_no=0
    while IFS= read -r line; do
      line_no=$((line_no + 1))

      # Collect allowed-literal names for this line: parse any
      # `# allow-hardcoded: <literal> reason: ...` marker on PREV line
      # OR appearing as a same-line suffix comment.
      declare -A allowed_here=()
      # PREV-line marker
      if [[ "$prev_line" =~ ^[[:space:]]*\#[[:space:]]+allow-hardcoded:[[:space:]]+(.+)[[:space:]]+reason:.*$ ]]; then
        cap="${BASH_REMATCH[1]}"
        cap="${cap%"${cap##*[![:space:]]}"}"
        allowed_here["$cap"]=1
      fi
      # SAME-line suffix marker (substring search — no need to anchor).
      if [[ "$line" == *"# allow-hardcoded:"* ]]; then
        # Extract everything after `# allow-hardcoded: ` up to ` reason:`
        tail_part="${line#*# allow-hardcoded: }"
        if [[ "$tail_part" == *" reason:"* ]]; then
          cap="${tail_part%% reason:*}"
          cap="${cap%"${cap##*[![:space:]]}"}"
          allowed_here["$cap"]=1
        fi
      fi

      # Skip pure-marker lines (a `# allow-hardcoded: ...` line is
      # documentation, not a hit even if its body contains the literal it
      # names). Detect: line matches the marker regex with no leading
      # code before the `#`.
      is_pure_marker=0
      if [[ "$line" =~ ^[[:space:]]*\#[[:space:]]+allow-hardcoded:[[:space:]]+ ]]; then
        is_pure_marker=1
      fi

      if [ "$is_pure_marker" -eq 0 ]; then
        for literal in "${FIXED_LITERALS[@]}"; do
          if [[ "$line" == *"$literal"* ]] && [ -z "${allowed_here[$literal]:-}" ]; then
            EXT_DRIFT_HITS+=("DRIFT (extended-scope): $src_file:$line_no contains '$literal'. Replace with \$VAR (preferred) — source zskills-resolve-config.sh if needed — OR add on the line ABOVE: # allow-hardcoded: $literal reason: <why>")
            EXT_DRIFT_FAIL=1
          fi
        done
        for pattern in "${REGEX_PATTERNS[@]}"; do
          if [[ "$line" =~ $pattern ]] && [ -z "${allowed_here[$pattern]:-}" ]; then
            EXT_DRIFT_HITS+=("DRIFT (extended-scope): $src_file:$line_no matches forbidden regex '$pattern'. Replace with \$VAR (preferred), OR add on the line ABOVE: # allow-hardcoded: $pattern reason: <why>")
            EXT_DRIFT_FAIL=1
          fi
        done
      fi

      prev_line="$line"
      unset allowed_here
    done < "$src_file"
  done

  if [ "$EXT_DRIFT_FAIL" -eq 0 ]; then
    pass "no skill-file drift hardcodes in extended scope (hooks/, scripts/, *.py)"
  else
    fail "extended-scope drift hardcodes detected" "${#EXT_DRIFT_HITS[@]} hit(s)"
    for h in "${EXT_DRIFT_HITS[@]}"; do
      printf '    %s\n' "$h" >&2
    done
  fi
fi

echo ""
echo "=== Worktree-test blockquote structural AC ==="
# WI 4.6 — Phase 2 WI 2.2 migrated the worktree-test recipe blockquote at
# skills/run-plan/modes/execute-phase.md from raw `npm start` / `npm run test:all` /
# `.test-results.txt` literals to `$DEV_SERVER_CMD` / `$FULL_TEST_CMD` /
# `$TEST_OUTPUT_FILE`. This AC mechanizes the structural invariant so a
# future agent can't silently revert one of the substitutions and have
# only the deny-list catch it (or worse, slip past as a non-fence literal).
BQ_TMP=$(mktemp)
awk '/^[[:space:]]*> \*\*Worktree test recipe:\*\*/,/^[[:space:]]*8\. \*\*No steps skipped/' \
    "$REPO_ROOT/skills/run-plan/modes/execute-phase.md" > "$BQ_TMP"

if [ ! -s "$BQ_TMP" ]; then
  fail "worktree-test blockquote: extracted bounds non-empty" "awk produced 0 lines — anchors drifted?"
elif grep -qE 'npm start|npm run test:all|\.test-results\.txt' "$BQ_TMP"; then
  fail "worktree-test blockquote: no raw literal" "raw literal in $BQ_TMP — see $REPO_ROOT/skills/run-plan/modes/execute-phase.md"
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

# Substitution-discipline rule (anchored by the "Never hardcode" prose
# header) must enumerate all 3 vars. Content-anchored — robust against
# upstream edits that shift line numbers.
DISCIPLINE_BLOCK=$(awk '/\*\*Never hardcode `npm run test:all`/,/^$/' "$REPO_ROOT/skills/run-plan/SKILL.md")
if echo "$DISCIPLINE_BLOCK" | grep -q '\$DEV_SERVER_CMD' \
   && echo "$DISCIPLINE_BLOCK" | grep -q '\$FULL_TEST_CMD' \
   && echo "$DISCIPLINE_BLOCK" | grep -q '\$TEST_OUTPUT_FILE'; then
  pass "substitution-discipline (Never-hardcode block) names all 3 vars"
else
  fail "substitution-discipline (Never-hardcode block) names all 3 vars" "block: $DISCIPLINE_BLOCK"
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
  # First positional arg is a single root (kept for callers that pass one
  # root); additional roots may be passed as a comma-separated list via
  # the 4th positional (root2) — caller convenience for two-root scans.
  local target_root="$1"
  local fail_var_name="$2"
  local hits_var_name="$3"
  local extra_root="${4:-}"
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
  done < <(
    if [ -n "$extra_root" ]; then
      find "$target_root" "$extra_root" -name '*.md' | sort
    else
      find "$target_root" -name '*.md' | sort
    fi
  )
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
mkdir -p "$POS_FIXTURE_DIR/skills/syn-pass" "$POS_FIXTURE_DIR/skills/syn-pass-dualpath" "$POS_FIXTURE_DIR/skills/syn-fail"
cat > "$POS_FIXTURE_DIR/skills/syn-pass/SKILL.md" <<'PASS_FIXTURE'
# syn-pass

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
echo "$FULL_TEST_CMD"
```
PASS_FIXTURE
# Phase 3 W3.5 (D6) / PLUGIN_LANE_ROOT_RESOLUTION_FIX Phase 3: the lane-portable
# dual-path source form MUST be accepted by the per-fence sourcing-discipline
# check just like the legacy one-liner. Both branches reference
# zskills-resolve-config.sh, so the fence-local preamble detector (substring
# match) recognizes it.
#
# Root-resolution-fix rewrite: this fixture previously carried the OLD
# `:-`-guarded form (`[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f ... ]`). That
# form is now FORBIDDEN by the resolution-fence-form assertion added below
# (it never substitutes mirror-less: the `${CLAUDE_PLUGIN_ROOT:-}` guard
# expands empty and short-circuits the working `-f` test). Rewritten to the
# NEW idiom — a bare `${CLAUDE_PLUGIN_ROOT}` `-f` test, NO `:-` guard. It still
# passes the positive-side scan because both branches retain the
# `zskills-resolve-config.sh` substring the preamble detector keys on.
cat > "$POS_FIXTURE_DIR/skills/syn-pass-dualpath/SKILL.md" <<'PASS_DUALPATH_FIXTURE'
# syn-pass-dualpath

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
echo "$FULL_TEST_CMD"
```
PASS_DUALPATH_FIXTURE
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

# Synthetic-PASS (dual-path) case: scan only syn-pass-dualpath; expect 0 hits.
# Asserts the Phase 3 W3.5/D6 two-line dual-path source form is accepted.
SYN_DUALPATH_FAIL=0
SYN_DUALPATH_HITS=()
scan_positive_side "$POS_FIXTURE_DIR/skills/syn-pass-dualpath" SYN_DUALPATH_FAIL SYN_DUALPATH_HITS
if [ "$SYN_DUALPATH_FAIL" -eq 0 ]; then
  pass "positive-side synthetic-PASS (dual-path): two-line CLAUDE_PLUGIN_ROOT fallback source form accepted"
else
  fail "positive-side synthetic-PASS (dual-path): should accept the two-line dual-path source form" "${SYN_DUALPATH_HITS[*]:-no hits}"
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

# Real-tree case: scan current skills/ AND block-diagram/ — expect 0 drift
# after Phase 2 migration. block-diagram/ added under #458 closure (the
# companion deny-list scanner above already extends to block-diagram/; the
# positive-side scanner extends here for symmetry — same surface PR #454
# swept).
REAL_POS_FAIL=0
REAL_POS_HITS=()
scan_positive_side "$REPO_ROOT/skills" REAL_POS_FAIL REAL_POS_HITS "$REPO_ROOT/block-diagram"
if [ "$REAL_POS_FAIL" -eq 0 ]; then
  pass "positive-side real-tree: every fence using a config-var also sources zskills-resolve-config.sh"
else
  fail "positive-side real-tree: ${#REAL_POS_HITS[@]} fence(s) reference config-vars without preamble" "see hits below"
  for h in "${REAL_POS_HITS[@]}"; do
    printf '    %s\n' "$h" >&2
  done
fi

# ════════════════════════════════════════════════════════════════════════
# PLUGIN_LANE_ROOT_RESOLUTION_FIX Phase 3 — resolution-fence-form lock-in.
#
# Two invariants the new lane-portable resolution idiom DEPENDS ON, codified
# so a future reflex cannot silently re-break the plugin lane mirror-less:
#
#   F-form: skill `.md` resolution fences must NOT use the `:-`-GUARDED form
#           (`[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f ... ]`) NOR the
#           `:-`-DEFAULT form (`${CLAUDE_PLUGIN_ROOT:-$...}`) around the
#           zskills-resolve-config.sh / zskills-paths.sh source. Both are
#           the BROKEN pre-fix forms: the `:-` guard expands to empty on the
#           legacy lane AND mirror-less it never substitutes the plugin path,
#           so the `-f` test short-circuits and resolution falls to an absent
#           mirror. The correct form is a BARE `${CLAUDE_PLUGIN_ROOT}` `-f`
#           test (no `:-`), which substitutes to the shipped path on the
#           plugin lane and expands empty→else-branch on the legacy lane.
#
#   F1 (set -u): a resolution fence must NOT be preceded by `set -u` /
#           `set -euo pipefail` on the line(s) immediately above it. The new
#           idiom's bare `${CLAUDE_PLUGIN_ROOT}` token is UNBOUND on the
#           legacy lane; under `set -u` it aborts ("unbound variable"). Prod
#           skill fences never run under `set -u`, so this is safe — this
#           assertion is the guardrail that keeps it so.
#
# SCOPE: skill `.md` SOURCE ONLY (skills/**, block-diagram/**). Deliberately
# NOT `.sh` scripts (verify-install.sh etc. legitimately keep `:-` defaults)
# and NOT hooks/** (hooks legitimately branch on `${CLAUDE_PLUGIN_ROOT:-}`).
#
# F5 honesty: these are STATIC source assertions over the rendered `.md`. They
# lock the FORM of the fence; the runtime FAIL→PASS proof of mirror-less
# resolution lives in tests/test-plugin-mirrorless-resolution.sh (shell
# self-bootstrap) and the attended tests/test-plugin-live-load.sh (harness
# substitution) — neither of which a static scan can substitute for.
# ════════════════════════════════════════════════════════════════════════

# scan_resolution_fence_forms <root> <fail-var> <hits-var> [extra-root]
#   For each *.md under <root> (+ optional <extra-root>), flag:
#     (a) a `${CLAUDE_PLUGIN_ROOT:-` occurrence (guard OR default) on a line
#         that also references zskills-resolve-config.sh or zskills-paths.sh
#         (i.e. a RESOLUTION fence, not an incidental token);
#     (b) a `set -u` / `set -euo` line that appears within 3 lines ABOVE a
#         line containing a bare-`${CLAUDE_PLUGIN_ROOT}` resolution `-f` test.
scan_resolution_fence_forms() {
  local target_root="$1" fail_var_name="$2" hits_var_name="$3" extra_root="${4:-}"
  local local_fail=0
  local -a local_hits=()
  local skill_file rel
  while IFS= read -r skill_file; do
    [ -f "$skill_file" ] || continue
    rel="${skill_file#$REPO_ROOT/}"
    # (a) `:-`-guarded / `:-`-default resolution form.
    #     Line carries BOTH `${CLAUDE_PLUGIN_ROOT:-` AND a resolver script name.
    while IFS=: read -r ln content; do
      [ -n "$ln" ] || continue
      local_hits+=("RESOLUTION-FENCE-FORM (\`:-\`): $rel:$ln uses a \`\${CLAUDE_PLUGIN_ROOT:-...}\` guard/default on a resolution-source line. This is the BROKEN pre-fix form (never substitutes mirror-less). Use a bare \`\${CLAUDE_PLUGIN_ROOT}\` \`-f\` test with NO \`:-\`. → $content")
      local_fail=1
    done < <(grep -nE '\$\{CLAUDE_PLUGIN_ROOT:-' "$skill_file" \
             | grep -E 'zskills-resolve-config\.sh|zskills-paths\.sh' || true)
    # (b) `set -u` / `set -euo` immediately above a bare-token resolution fence.
    #     awk: remember the last `set -u`/`set -euo` line number; when a
    #     bare-`${CLAUDE_PLUGIN_ROOT}` `-f` resolution test appears within 3
    #     lines after it (and no intervening fence-closer), flag it.
    while IFS=: read -r ln content; do
      [ -n "$ln" ] || continue
      local_hits+=("RESOLUTION-FENCE-FORM (set -u above fence): $rel:$ln has \`set -u\`/\`set -euo\` within 3 lines above a bare-\`\${CLAUDE_PLUGIN_ROOT}\` resolution fence. The new idiom's bare token is UNBOUND on the legacy lane and aborts under \`set -u\`. Remove the \`set -u\` above the fence. → $content")
      local_fail=1
    done < <(awk '
      /set -u|set -euo/ { setu_line = NR; setu_text = $0 }
      # a bare ${CLAUDE_PLUGIN_ROOT} resolution -f test (NOT the :- form)
      /\[[[:space:]]+-f[[:space:]]+"\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/update-zskills\/scripts\/(zskills-resolve-config|zskills-paths)\.sh"/ {
        if (setu_line > 0 && (NR - setu_line) <= 3) {
          printf "%d:%s\n", setu_line, setu_text
          setu_line = 0
        }
      }
    ' "$skill_file" || true)
  done < <(
    if [ -n "$extra_root" ]; then
      find "$target_root" "$extra_root" -name '*.md' | sort
    else
      find "$target_root" -name '*.md' | sort
    fi
  )
  printf -v "$fail_var_name" '%s' "$local_fail"
  if [ "$local_fail" -eq 1 ]; then
    for h in "${local_hits[@]}"; do
      eval "$hits_var_name+=(\"\$h\")"
    done
  fi
}

# ── Synthetic FAIL/PASS fixtures proving each assertion FIRES and ALLOWS ──
RF_FIXTURE_DIR=$(mktemp -d)
mkdir -p "$RF_FIXTURE_DIR/skills/rf-fail-guard" \
         "$RF_FIXTURE_DIR/skills/rf-fail-default" \
         "$RF_FIXTURE_DIR/skills/rf-fail-setu" \
         "$RF_FIXTURE_DIR/skills/rf-pass"

# FAIL fixture A: `:-`-guarded resolution form (the broken pre-fix form).
cat > "$RF_FIXTURE_DIR/skills/rf-fail-guard/SKILL.md" <<'RF_FAIL_GUARD'
# rf-fail-guard

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```
RF_FAIL_GUARD

# FAIL fixture B: `:-`-default resolution form.
cat > "$RF_FIXTURE_DIR/skills/rf-fail-default/SKILL.md" <<'RF_FAIL_DEFAULT'
# rf-fail-default

```bash
. "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_PROJECT_DIR/.claude}/skills/update-zskills/scripts/zskills-paths.sh"
```
RF_FAIL_DEFAULT

# FAIL fixture C: `set -u` immediately above a bare-token resolution fence.
cat > "$RF_FIXTURE_DIR/skills/rf-fail-setu/SKILL.md" <<'RF_FAIL_SETU'
# rf-fail-setu

```bash
set -u
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```
RF_FAIL_SETU

# PASS fixture: the NEW idiom — bare token, NO `:-`, NO `set -u` above.
cat > "$RF_FIXTURE_DIR/skills/rf-pass/SKILL.md" <<'RF_PASS'
# rf-pass

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```
RF_PASS

# FAIL-fixture A proof (`:-`-guard fires).
RF_FAIL_GUARD_FAIL=0
RF_FAIL_GUARD_HITS=()
scan_resolution_fence_forms "$RF_FIXTURE_DIR/skills/rf-fail-guard" RF_FAIL_GUARD_FAIL RF_FAIL_GUARD_HITS
if [ "$RF_FAIL_GUARD_FAIL" -eq 1 ] && [ "${#RF_FAIL_GUARD_HITS[@]}" -ge 1 ]; then
  pass "resolution-fence-form synthetic-FAIL (\`:-\`-guard): broken guard form flagged"
else
  fail "resolution-fence-form synthetic-FAIL (\`:-\`-guard): should flag the guard form" "fail=$RF_FAIL_GUARD_FAIL hits=${#RF_FAIL_GUARD_HITS[@]}"
fi

# FAIL-fixture B proof (`:-`-default fires).
RF_FAIL_DEFAULT_FAIL=0
RF_FAIL_DEFAULT_HITS=()
scan_resolution_fence_forms "$RF_FIXTURE_DIR/skills/rf-fail-default" RF_FAIL_DEFAULT_FAIL RF_FAIL_DEFAULT_HITS
if [ "$RF_FAIL_DEFAULT_FAIL" -eq 1 ] && [ "${#RF_FAIL_DEFAULT_HITS[@]}" -ge 1 ]; then
  pass "resolution-fence-form synthetic-FAIL (\`:-\`-default): broken default form flagged"
else
  fail "resolution-fence-form synthetic-FAIL (\`:-\`-default): should flag the default form" "fail=$RF_FAIL_DEFAULT_FAIL hits=${#RF_FAIL_DEFAULT_HITS[@]}"
fi

# FAIL-fixture C proof (`set -u` above fence fires).
RF_FAIL_SETU_FAIL=0
RF_FAIL_SETU_HITS=()
scan_resolution_fence_forms "$RF_FIXTURE_DIR/skills/rf-fail-setu" RF_FAIL_SETU_FAIL RF_FAIL_SETU_HITS
if [ "$RF_FAIL_SETU_FAIL" -eq 1 ] && [ "${#RF_FAIL_SETU_HITS[@]}" -ge 1 ]; then
  pass "resolution-fence-form synthetic-FAIL (set -u above fence): \`set -u\`-above-resolution-fence flagged"
else
  fail "resolution-fence-form synthetic-FAIL (set -u above fence): should flag set -u above fence" "fail=$RF_FAIL_SETU_FAIL hits=${#RF_FAIL_SETU_HITS[@]}"
fi

# PASS-fixture proof (new idiom allowed).
RF_PASS_FAIL=0
RF_PASS_HITS=()
scan_resolution_fence_forms "$RF_FIXTURE_DIR/skills/rf-pass" RF_PASS_FAIL RF_PASS_HITS
if [ "$RF_PASS_FAIL" -eq 0 ]; then
  pass "resolution-fence-form synthetic-PASS: bare-token new idiom (no \`:-\`, no \`set -u\`) accepted"
else
  fail "resolution-fence-form synthetic-PASS: should accept the new idiom" "${RF_PASS_HITS[*]:-no hits}"
fi

rm -rf "$RF_FIXTURE_DIR"

# Real-tree case: Phase 1+2 removed every `:-`-guarded/`:-`-default resolution
# fence and put no `set -u` above any fence — so expect 0 hits. This LOCKS the
# invariant against future regression.
REAL_RF_FAIL=0
REAL_RF_HITS=()
scan_resolution_fence_forms "$REPO_ROOT/skills" REAL_RF_FAIL REAL_RF_HITS "$REPO_ROOT/block-diagram"
if [ "$REAL_RF_FAIL" -eq 0 ]; then
  pass "resolution-fence-form real-tree: no \`:-\`-guarded/\`:-\`-default resolution fences and no \`set -u\` above any resolution fence (skills/** + block-diagram/**)"
else
  fail "resolution-fence-form real-tree: ${#REAL_RF_HITS[@]} broken resolution-fence form(s)" "see hits below"
  for h in "${REAL_RF_HITS[@]}"; do
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

# Issue #185 + #186 — propagate-via-prose discipline rules. Both
# CLAUDE_TEMPLATE.md (the source) and .claude/rules/zskills/managed.md
# (rendered from the template via /update-zskills Step B; auto-loaded
# from .claude/rules/ at session start) must contain the load-bearing
# literals from each rule. Drift here means the rule silently
# disappears from one surface or the other; lock both. Prior to #432
# this also scanned root CLAUDE.md, but post-#432 these shared rules
# live exclusively in CLAUDE_TEMPLATE.md → managed.md; root CLAUDE.md
# now holds only project-specific Architecture + zskills-author-only
# rules. The render-equivalence between template and managed.md is
# locked by tests/test-managed-md-up-to-date.sh.
echo "=== Propagation-discipline prose rules (issues #185, #186) ==="
for prose_file in "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$REPO_ROOT/.claude/rules/zskills/managed.md"; do
  rel="${prose_file#$REPO_ROOT/}"
  if grep -qF 'Memory anchors are agent-local notes' "$prose_file"; then
    pass "[propagation-prose] $rel contains memory-anchor rule literal (#186)"
  else
    fail "[propagation-prose] $rel" "missing literal: 'Memory anchors are agent-local notes' (#186)"
  fi
  if grep -qF 'Never call `gh pr create` or `gh pr merge --auto` directly when landing a PR' "$prose_file"; then
    pass "[propagation-prose] $rel contains PR-landing-discipline rule literal (#185)"
  else
    fail "[propagation-prose] $rel" "missing literal: 'Never call \`gh pr create\` or \`gh pr merge --auto\` directly when landing a PR' (#185)"
  fi
  # Cron-fire recognition rule: cron fires arrive as plain Human turns with
  # no `<command-name>` envelope; recipient agents must recognize the
  # `Run /<skill> ...` shape, read SKILL.md, execute inline, and never
  # CronDelete on a confused fire. Memory anchors don't propagate, so this
  # rule must live in both surfaces.
  if grep -qF '## Cron-fired prompts' "$prose_file"; then
    pass "[propagation-prose] $rel contains '## Cron-fired prompts' heading"
  else
    fail "[propagation-prose] $rel" "missing heading: '## Cron-fired prompts'"
  fi
  if grep -qF 'Treat any user-shaped turn whose entire content starts with' "$prose_file"; then
    pass "[propagation-prose] $rel contains cron-fire recognition contract literal"
  else
    fail "[propagation-prose] $rel" "missing literal: 'Treat any user-shaped turn whose entire content starts with'"
  fi
  if grep -qF 'Never `CronDelete` on the strength of a confused fire' "$prose_file"; then
    pass "[propagation-prose] $rel contains 'no-CronDelete-on-confusion' rule literal"
  else
    fail "[propagation-prose] $rel" "missing literal: 'Never \`CronDelete\` on the strength of a confused fire'"
  fi
done

echo ""
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
echo "=== Reports-dir writer placement (issue #217) ==="
# Writer skills (run-plan, verify-changes, fix-issues) MUST emit work-trail
# reports (plan-*, verify-*, SPRINT_REPORT) under $ZSKILLS_REPORTS_DIR — NOT
# $ZSKILLS_AUDIT_DIR. PLAN_REPORT.md, FIX_REPORT.md, briefing-*, debug dumps
# legitimately stay at AUDIT_DIR and are not matched by this pattern.
for skill in run-plan verify-changes fix-issues; do
  skill_dir="$REPO_ROOT/skills/$skill"
  [ -d "$skill_dir" ] || continue
  leak=$(grep -rE '\$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)' "$skill_dir") || \
    [ "$?" -eq 1 ] || { echo "FAIL: grep error" >&2; exit 1; }
  if [ -n "$leak" ]; then
    fail "[reports-dir-placement] $skill" "Found legacy '\$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)' references — must use \$ZSKILLS_REPORTS_DIR (issue #217). Hits:
$leak"
  else
    pass "[reports-dir-placement] $skill: no legacy AUDIT_DIR-for-reports references"
  fi
done

echo ""
echo "=== .zskills/ umbrella cleanliness (issue #217) ==="
# Allow-list: empty today, but exists so future legitimate force-adds (e.g., a
# zskills-versions.lock file) can be added by editing the file rather than
# editing this assertion. Format: one path per line, # for comments.
ALLOWLIST="$REPO_ROOT/tests/zskills-tracked-allowlist.txt"
if [ -f "$ALLOWLIST" ]; then
  allowed=$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" | sort -u)
else
  allowed=""
fi
tracked=$(git -C "$REPO_ROOT" ls-files -- ".zskills/" | sort -u)
if [ -n "$allowed" ]; then
  leaked=$(comm -23 <(echo "$tracked") <(echo "$allowed"))
else
  leaked="$tracked"
fi
leaked_count=$(echo "$leaked" | grep -c .) || [ "$?" -eq 1 ] || { echo "FAIL: grep error" >&2; exit 1; }
if [ "$leaked_count" -eq 0 ]; then
  pass "[.zskills-umbrella] no force-tracked files under .zskills/ outside allow-list (issue #217)"
else
  fail "[.zskills-umbrella] $leaked_count force-tracked files under .zskills/ outside allow-list (must be 0; issue #217). First 10:" \
"$(echo "$leaked" | head -10)"
fi

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
    # Phase 1b: block-diagram/<name>/ is also an accepted source root
    # (mirrored via `bash scripts/mirror-skill.sh block-diagram/<name>`).
    if [ -f "$REPO_ROOT/block-diagram/$name/SKILL.md" ]; then
      src_dir="$REPO_ROOT/block-diagram/$name"
    else
      # No source — must be on the allow-list.
      if [[ " $MIRROR_ONLY_OK " == *" $name "* ]]; then
        pass "skill $name: mirror-only (allow-listed, skipped)"
        continue
      fi
      fail "mirrored skill $name: no source counterpart and not on MIRROR_ONLY_OK allow-list" \
        "orphaned mirror — delete .claude/skills/$name or add a source dir"
      continue
    fi
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
# Annotation form (Phase 2 added these inline alongside the migration;
# #1049 reworded the client-facing breadcrumb to a maintainer note):
#
#     run `$FULL_TEST_CMD` (canonical form — maintainers: see
#       `references/canonical-config-prelude.md` §1 in the zskills source)
#       before committing.
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
          # (d) maintainer-note pointer-prose: `(canonical form — maintainers:
          #     see references/canonical-config-prelude.md §1 ...)` — #1049
          #     reworded the client-facing `(resolve via ...)` breadcrumb into
          #     an explicit maintainer note so it no longer reads as a path a
          #     client resolves. The annotation discipline is unchanged: every
          #     prose $VAR site still carries a nearby resolution annotation;
          #     this form is the maintainer-facing spelling of it.
          if [[ "$wline" == *"zskills-resolve-config.sh"* ]] \
             || [[ "$wline" =~ CONFIG_CONTENT=\$\(cat ]] \
             || [[ "$wline" =~ \(resolved\ from\ config ]] \
             || [[ "$wline" =~ \(resolve\ via ]] \
             || [[ "$wline" =~ \(canonical\ form ]]; then
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
done < <(find "$REPO_ROOT/skills" "$REPO_ROOT/block-diagram" -name '*.md' | sort)

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
echo "=== /qe-audit — ban audit-not-done caveats (issue #404) ==="
# Issue #404: /qe-audit-filed issue bodies trend conservative with
# "Audit-not-done" / "Larger-than-issue" framings instead of running
# the cheap inline audit. The SKILL.md prose must explicitly ban those
# caveats and require validating evidence before filing cross-cutting
# concerns. These checks lock the prose anchor + the bar-for-filing
# language so future edits can't silently drop the rule.
check_fixed qe-audit "ban-caveats heading"                'Ban caveats: no "audit-not-done" hedges in filed bodies'
check_fixed qe-audit "bar-for-filing structural rule"     'Bar for filing a structural / cross-cutting issue'
check_fixed qe-audit "speculation never earns a filing"   'Speculation alone'
check_fixed qe-audit "worked example: past failure #380"  'past failure #380'
check_fixed qe-audit "worked example: past failure #390"  'past failure #390'
check_fixed qe-audit "bash-mode sweep echoes the rule"    'Ban caveats: the Commit Audit Step 6'

echo ""
echo "=== /qe-audit — TIGHT-BAR + filter taxonomy + cadence/recovery (issue #637) ==="
# Issue #637: SKILL.md body had drifted from operational calibration —
# TIGHT-BAR 3-question self-triage, do/DON'T filter taxonomy, family-pattern
# consolidation, cadence-stretch rule, and orchestrator-recovery rule lived
# only in the cron-fired prompt. Fresh-session loads (post-/clear) dispatched
# /qe-audit with none of these → regression to passes 1-11 yield patterns.
# These pins lock the calibration into the body so cron-prompt drift cannot
# erase it again. 12 checks: 6 fingerprints × 2 files (source + mirror).
for QE_FILE in "$REPO_ROOT/skills/qe-audit/SKILL.md" "$REPO_ROOT/.claude/skills/qe-audit/SKILL.md"; do
  QE_REL="${QE_FILE#$REPO_ROOT/}"
  for QE_FP_LABEL in \
    "TIGHT-BAR triage section heading|TIGHT-BAR triage and filter rules" \
    "falsifying-trace question|Verified falsifying trace" \
    "do NOT file filter bucket|Filter — do NOT file" \
    "family-pattern consolidation rule|Family-pattern consolidation" \
    "cadence-stretch rule|Cadence-stretch rule" \
    "recovery rule (orchestrator drift)|Recovery rule"
  do
    QE_LABEL="${QE_FP_LABEL%%|*}"
    QE_PAT="${QE_FP_LABEL#*|}"
    if grep -qF -- "$QE_PAT" "$QE_FILE" 2>/dev/null; then
      pass "[$QE_REL] $QE_LABEL"
    else
      fail "[$QE_REL] $QE_LABEL" "missing fingerprint: $QE_PAT"
    fi
  done
done

echo ""
echo "=== /update-zskills — Step 0.5 parent-scoped JSON extraction (issue #428) ==="
# Issue #428: Step 0.5 "Read Config" in skills/update-zskills/SKILL.md
# teaches a config-extraction recipe using bash regex on JSON. The
# fields listed below all live INSIDE a parent object in
# .claude/zskills-config.json — unscoped regex (the
# `\"<field>\"[[:space:]]*:` form anchored at the start of the
# pattern with no parent prefix) silently matches the first
# occurrence regardless of which block declared it, exactly the
# bug class fixed in scripts by PRs #422 (#400) and #423 (#395).
# The prose recipe must use the parent-scoped form
# (`\"<parent>\"[[:space:]]*:[[:space:]]*\{[^}]*\"<field>\"...`).
# The negative check below greps for the unscoped pattern
# (`=~ \"<field>\"` — i.e. `=~ ` directly followed by the field
# key with no parent prefix). Scoped patterns will not match
# because they begin with `=~ \"<parent>\"`.
#
# This tripwire fires on both the source and the .claude/ mirror so
# any future regression on either side is caught.
ZSKILLS_FIELDS_PARENTED=(
  "unit_cmd"          # parent: testing  (#395)
  "full_cmd"          # parent: testing  (#395)
  "output_file"       # parent: testing  (#395)
  "main_repo_path"    # parent: dev_server
  "auth_bypass"       # parent: ui
  "main_protected"    # parent: execution  (#400)
  "landing"           # parent: execution  (#400)
  "branch_prefix"     # parent: execution
  "auto_fix"          # parent: ci
  "max_fix_attempts"  # parent: ci
  "co_author"         # parent: commit
)
for _zsk_field in "${ZSKILLS_FIELDS_PARENTED[@]}"; do
  check_not_in_file update-zskills SKILL.md \
    "Step 0.5 unscoped regex for parented field '$_zsk_field'" \
    "=~ \\\\\"${_zsk_field}\\\\\""
  check_not_in_file .claude/skills/update-zskills SKILL.md \
    ".claude mirror: Step 0.5 unscoped regex for parented field '$_zsk_field'" \
    "=~ \\\\\"${_zsk_field}\\\\\""
done
# Positive: at least one scoped extraction must be present so the
# recipe still teaches the right pattern (catches accidental whole-
# block deletion).
check_fixed update-zskills "Step 0.5 scoped pattern (canonical form, testing.unit_cmd)" \
  '\"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"unit_cmd\"'
check_fixed .claude/skills/update-zskills ".claude mirror: scoped pattern present" \
  '\"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"unit_cmd\"'

echo '=== Mode-file `git rebase origin/main` HEAD precondition (issue #429) ==='
# Issue #429: PR #419 added a `HEAD == \$BRANCH` precondition to
# scripts/pr-rebase.sh:82-88 (exit 14, REASON=wrong-current-branch) so
# the callable helper can't silently rebase the wrong branch on CWD
# drift. But agent-prose mode files run their OWN inline `git rebase
# origin/main` that bypasses that helper — same #397 symptom resurfaces
# if the guard isn't ported inline. This check asserts: every literal
# bash `git rebase origin/main` invocation in a `skills/**/modes/*.md`
# file is preceded (within the prior 20 lines) by a HEAD check
# (`rev-parse --abbrev-ref HEAD` or `symbolic-ref`).
#
# Excluded by design (these are NOT bash invocations the agent runs
# inline — they are echoed recovery instructions or prose commentary):
#   - lines starting with `echo` / `printf` (user-facing recovery hints)
#   - lines beginning with `#` (comments / agent prompt prose)
MODE_FILES=$(find "$REPO_ROOT/skills" -path '*/modes/*.md' -type f 2>/dev/null)
GUARD_VIOLATIONS=0
for mf in $MODE_FILES; do
  # Find every line that contains `git rebase origin/main` as an actual
  # bash invocation. Strip leading whitespace before deciding whether
  # the line is a comment / echo / printf.
  while IFS=: read -r MATCH_LN _; do
    [ -z "$MATCH_LN" ] && continue
    LINE=$(sed -n "${MATCH_LN}p" "$mf")
    # Strip leading whitespace.
    STRIPPED="${LINE#"${LINE%%[![:space:]]*}"}"
    case "$STRIPPED" in
      \#*|echo*|printf*|\"*|\'*) continue ;;  # comment, echo, printf, or string literal — not an invocation
    esac
    # Compute the start of the 20-line preceding window.
    START=$((MATCH_LN - 20))
    [ "$START" -lt 1 ] && START=1
    END=$((MATCH_LN - 1))
    [ "$END" -lt 1 ] && END=1
    WINDOW=$(sed -n "${START},${END}p" "$mf")
    if echo "$WINDOW" | grep -qE 'rev-parse --abbrev-ref HEAD|symbolic-ref'; then
      pass "$(basename "$(dirname "$(dirname "$mf")")")/modes/$(basename "$mf"):${MATCH_LN} HEAD guard present"
    else
      fail "$(basename "$(dirname "$(dirname "$mf")")")/modes/$(basename "$mf"):${MATCH_LN} missing HEAD guard before \`git rebase origin/main\`" "rev-parse --abbrev-ref HEAD within preceding 20 lines"
      GUARD_VIOLATIONS=$((GUARD_VIOLATIONS + 1))
    fi
  done < <(grep -n 'git rebase origin/main' "$mf" 2>/dev/null)
done

echo "=== sanitize-pipeline-id.sh wraps at every PIPELINE_ID= construct-site (issue #459) ==="
# CLAUDE.md `## Tracking markers` mandates: every constructed PIPELINE_ID
# MUST be passed through sanitize-pipeline-id.sh before being written to
# disk. Four skills (run-plan, commit/modes/pr.md, draft-plan, refine-plan)
# previously skipped this; PR #459 added the canonical wrap line after each
# construct-site assignment. This tripwire locks the wrap count by file —
# adding a 15th construct-site to run-plan without also adding the wrap
# (or vice-versa) fails the assertion, in either direction.
#
# Counts here are LITERAL EQUALITY (not >=) so drift is visible from
# either side. If a future PR genuinely adds another construct-site,
# update the literal here in the same commit that adds the wrap.
check_sanitize_count() {
  local skill_path="$1" expected="$2" label="$3"
  local actual
  actual=$(grep -c 'sanitize-pipeline-id' "$REPO_ROOT/$skill_path" 2>/dev/null || echo 0)
  if [ "$actual" = "$expected" ]; then
    pass "$label: $actual sanitize wraps (== $expected)"
  else
    fail "$label: found $actual sanitize wraps, expected exactly $expected" "$expected sanitize-pipeline-id.sh wraps in $skill_path"
  fi
}
check_sanitize_count "skills/run-plan/SKILL.md"                       6 "skills/run-plan/SKILL.md"
check_sanitize_count "skills/run-plan/modes/execute-phase.md"        10 "skills/run-plan/modes/execute-phase.md"
check_sanitize_count "skills/run-plan/subcommands/stop-next-status.md" 1 "skills/run-plan/subcommands/stop-next-status.md"
check_sanitize_count "skills/commit/modes/pr.md"      1 "skills/commit/modes/pr.md"
check_sanitize_count "skills/draft-plan/SKILL.md"     5 "skills/draft-plan/SKILL.md"
check_sanitize_count "skills/refine-plan/SKILL.md"    3 "skills/refine-plan/SKILL.md"
check_sanitize_count "skills/verify-changes/SKILL.md" 4 "skills/verify-changes/SKILL.md"

echo ""
echo "=== test-hooks.sh property-matrix axes preserved (issues #564 / #556 / #565) ==="
# The push-to-main bypass property-enumeration matrix in tests/test-hooks.sh
# (generic + project sections) is itself unprotected against silent
# shrinkage. If a future agent reverts the `for branch in main feat/test`
# HEAD-axis loop added by #556 or drops the `dest="${force}${refp}HEAD"`
# extension landed by #565, all 1400 HEAD-axis cases vanish — but the
# test still passes with 0 failures because the matrix just enumerates
# fewer cases. Issue #564 surfaced this hole: a load-bearing test net
# must itself be protected.
#
# These assertions are pure substring counts on tests/test-hooks.sh and
# fail-closed by construction: drop a loop header → count drops → FAIL.
# Counts are minimums (>=) rather than literal equality so a future PR
# can legitimately ADD a third matrix section without churning this gate.
HOOKS_TEST="$REPO_ROOT/tests/test-hooks.sh"

check_min_count() {
  local pattern="$1" expected_min="$2" label="$3" use_extended="$4"
  local actual
  if [ "$use_extended" = "E" ]; then
    actual=$(grep -cE "$pattern" "$HOOKS_TEST" 2>/dev/null || echo 0)
  else
    actual=$(grep -cF "$pattern" "$HOOKS_TEST" 2>/dev/null || echo 0)
  fi
  if [ "$actual" -ge "$expected_min" ]; then
    pass "$label: $actual matches (>= $expected_min)"
  else
    fail "$label: found $actual matches, expected >= $expected_min" "$pattern in tests/test-hooks.sh"
  fi
}

# Assertion A — branch-context axis: `for branch in main feat/test` must
# appear at least twice (once per matrix section: generic + project).
# Locks the #556 / #565 HEAD-axis branch-context loop in both sections.
check_min_count "for branch in main feat/test" 2 "branch-context axis preserved" F

# Assertion B — HEAD destination token: `dest="${force}${refp}HEAD"` must
# appear at least twice. This is the structural marker for the #565
# HEAD-axis extension (one per section). The non-HEAD matrix uses
# `dest="${force}${refp}${target}"` so this literal is unique to the
# HEAD-axis loops; counting it directly catches axis collapse.
check_min_count 'dest="\$\{force\}\$\{refp\}HEAD"' 2 "HEAD destination axis preserved" E

# Assertion C — primary target axis: `for target in main master feat/test`
# must appear at least twice (once per section). Locks the deny/allow
# matrix's non-HEAD target enumeration so a future revert can't shrink
# the base matrix either.
check_min_count "for target in main master feat/test" 2 "primary target axis preserved" F

# Assertion D — make_branch_repo helper function is defined. The #565
# HEAD-axis generic-hook loop depends on this helper to create a temp
# repo on each branch context. If the helper is deleted, the HEAD-axis
# loop silently errors out before any expect_*_from_repo runs.
check_min_count "^make_branch_repo\(\)" 1 "make_branch_repo helper defined" E

# Assertion E (issue #594) — synthetic-fixture paths in tests/test-hooks.sh
# MUST be PID-scoped so parallel worktrees running tests/run-all.sh
# concurrently don't `rm -rf` each other's mid-test fixtures (the race
# that produced 10/10 misses of `__TEST_LITERAL__` in the
# fixture-extension assertion). The literal source tokens carry `$$`
# verbatim; `grep -F` keeps `$$` as text (no shell expansion).
if grep -qF 'FIXTURE_EXT_DIR=/tmp/zskills-fixture-extension-test-$$' "$HOOKS_TEST"; then
  pass "fixture-extension-test path is PID-scoped (issue #594)"
else
  fail "fixture-extension-test path missing PID suffix (issue #594)" "expected FIXTURE_EXT_DIR=/tmp/zskills-fixture-extension-test-\$\$ in tests/test-hooks.sh"
fi
if grep -qF 'SKILL_DRIFT_FIXTURE=/tmp/zskills-warn-skill-drift-test-$$' "$HOOKS_TEST"; then
  pass "warn-skill-drift-test path is PID-scoped (issue #594)"
else
  fail "warn-skill-drift-test path missing PID suffix (issue #594)" "expected SKILL_DRIFT_FIXTURE=/tmp/zskills-warn-skill-drift-test-\$\$ in tests/test-hooks.sh"
fi

# ----------------------------------------------------------------------
# zskills-dashboard PLAN_COLUMNS / ISSUE_COLUMNS four-site synchronization
# ----------------------------------------------------------------------
# Locks the FULL-TUPLE-ORDERING (not substring presence — per plan DA9) of
# the column-list declarations across the four sites that must stay in
# sync for the Completed + Backlog sub-column feature (plan
# `plans/completed-backlog-sections.md`, Phase 5 W5.1).
#
# IMPORTANT asymmetry (Locked Decision D4 + W2.2 explicit reject):
# `server.py`'s `PLAN_COLUMNS` / `ISSUE_COLUMNS` tuples DELIBERATELY OMIT
# `"completed"` because `completed` is read-only on the API surface — the
# `_validate_queue_body` validator hard-rejects POSTs to it with literal
# error `"completed column is read-only"`. The frontend's `app.js`
# `PLAN_COLUMNS` / `ISSUE_COLUMNS` arrays DO include `"completed"` because
# the frontend RENDERS the completed band. The conformance patterns below
# encode that asymmetry — if a future refactor "fixes" the inconsistency
# by adding `completed` to the server tuples, this test will fail closed
# and force the change to be done deliberately.
#
# `collect.py` is iterative (it iterates `state.get("plans", {}).items()`
# / `state.get("issues", {}).items()` dynamically), so it doesn't have a
# literal tuple — instead a comment marker anchored to this test file is
# checked.
DASHBOARD_ROOT="$REPO_ROOT/skills/zskills-dashboard/scripts/zskills_monitor"
DASHBOARD_SERVER="$DASHBOARD_ROOT/server.py"
DASHBOARD_APPJS="$DASHBOARD_ROOT/static/app.js"
DASHBOARD_COLLECT="$DASHBOARD_ROOT/collect.py"

# Site 1: server.py PLAN_COLUMNS — 5 elements (#677 added discarded between
# backlog and completed — but server-side completed is OMITTED per D4, so
# server has 5 writable columns total).
if grep -qE 'PLAN_COLUMNS *= *\("drafted", *"reviewed", *"ready", *"backlog", *"discarded"\)' "$DASHBOARD_SERVER"; then
  pass "dashboard server.py PLAN_COLUMNS full-tuple-ordering (5 cols incl discarded, no completed — D4 + #677)"
else
  fail "dashboard server.py PLAN_COLUMNS full-tuple-ordering (5 cols incl discarded, no completed — D4 + #677)" 'expected PLAN_COLUMNS = ("drafted", "reviewed", "ready", "backlog", "discarded") in server.py'
fi

# Site 2: server.py ISSUE_COLUMNS — 3 elements, NO completed (D4).
if grep -qE 'ISSUE_COLUMNS *= *\("triage", *"ready", *"backlog"\)' "$DASHBOARD_SERVER"; then
  pass "dashboard server.py ISSUE_COLUMNS full-tuple-ordering (3 cols, no completed — D4)"
else
  fail "dashboard server.py ISSUE_COLUMNS full-tuple-ordering (3 cols, no completed — D4)" 'expected ISSUE_COLUMNS = ("triage", "ready", "backlog") in server.py'
fi

# Site 3: app.js PLAN_COLUMNS — 6 elements (#677 added discarded between
# backlog and completed). Ordering matters: → traversal from Backlog
# lands in Discarded.
if grep -qE 'const PLAN_COLUMNS *= *\["drafted", *"reviewed", *"ready", *"backlog", *"discarded", *"completed"\]' "$DASHBOARD_APPJS"; then
  pass "dashboard app.js PLAN_COLUMNS full-tuple-ordering (6 cols, with discarded + completed — #677)"
else
  fail "dashboard app.js PLAN_COLUMNS full-tuple-ordering (6 cols, with discarded + completed — #677)" 'expected const PLAN_COLUMNS = ["drafted", "reviewed", "ready", "backlog", "discarded", "completed"] in app.js'
fi

# Site 4: app.js ISSUE_COLUMNS — 4 elements WITH completed.
if grep -qE 'const ISSUE_COLUMNS *= *\["triage", *"ready", *"backlog", *"completed"\]' "$DASHBOARD_APPJS"; then
  pass "dashboard app.js ISSUE_COLUMNS full-tuple-ordering (4 cols, with completed)"
else
  fail "dashboard app.js ISSUE_COLUMNS full-tuple-ordering (4 cols, with completed)" 'expected const ISSUE_COLUMNS = ["triage", "ready", "backlog", "completed"] in app.js'
fi

# Site 5: app.js deepCloneQueues — anchored on `for (const c of PLAN_COLUMNS)`
# and `for (const c of ISSUE_COLUMNS)` symbol patterns. By reference these
# cover the full tuple — deepCloneQueues is the allocator that initializes
# every column key from the constant, so any column added to the constant
# is automatically allocated.
if grep -qE 'for \(const c of PLAN_COLUMNS\)' "$DASHBOARD_APPJS"; then
  pass "dashboard app.js deepCloneQueues iterates PLAN_COLUMNS by reference"
else
  fail "dashboard app.js deepCloneQueues iterates PLAN_COLUMNS by reference" 'expected for (const c of PLAN_COLUMNS) in app.js'
fi
if grep -qE 'for \(const c of ISSUE_COLUMNS\)' "$DASHBOARD_APPJS"; then
  pass "dashboard app.js deepCloneQueues iterates ISSUE_COLUMNS by reference"
else
  fail "dashboard app.js deepCloneQueues iterates ISSUE_COLUMNS by reference" 'expected for (const c of ISSUE_COLUMNS) in app.js'
fi

# Site 6: collect.py comment marker — documents the dynamic state-file
# column iteration as the synchronization point.
if grep -qF 'state-file column iteration — picks up new columns from PLAN_COLUMNS / ISSUE_COLUMNS dynamically; conformance: tests/test-skill-conformance.sh' "$DASHBOARD_COLLECT"; then
  pass "dashboard collect.py state-file column iteration marker present"
else
  fail "dashboard collect.py state-file column iteration marker present" 'expected comment "state-file column iteration ... conformance: tests/test-skill-conformance.sh" in collect.py'
fi

echo ""
echo "=== /qe-audit + /fix-issues — Files-to-change + scope-grep (#681) ==="
# Issue #681: /qe-audit must prescribe a `## Files to change` section in
# every filed issue body so implementers can grep for authoritative scope.
# /fix-issues must enforce a scope-grep verification step that cross-checks
# the agent's diff against all files named in the issue body.
check       qe-audit    "issue body format prescribes Files-to-change"   '## Files to change'
check       fix-issues  "impl-prompt scope-grep enforcement"             '[Ss]cope-grep verification'
check       fix-issues  "impl-prompt verifies each file in diff"         'git diff origin/main\.\.HEAD --name-only'

echo ""
echo "=== plugin hooks — line-2 # zskills-hook-version: stamp (W1.3 / D16(a)) ==="
# Every shipped non-canary hook script under hooks/ (all *.sh except
# canary*) PLUS the two *.template hooks must carry a line-2
# `# zskills-hook-version:` stamp. The shim's version-skew check
# (hooks/_lib/plugin-hook-skip-if-mirrored.sh) reads this stamp from both
# the plugin copy and the settings.json-registered copy; an absent stamp on
# either side forces a silent defer (D16(a) step 6), so a missing stamp is a
# correctness regression for dual-install hook double-fire prevention.
HOOK_STAMP_TARGETS=()
shopt -s nullglob
for _h in "$REPO_ROOT"/hooks/*.sh; do
  case "$(basename "$_h")" in
    canary*) continue ;;
  esac
  HOOK_STAMP_TARGETS+=("$_h")
done
for _h in "$REPO_ROOT"/hooks/*.sh.template; do
  HOOK_STAMP_TARGETS+=("$_h")
done
shopt -u nullglob
for _h in "${HOOK_STAMP_TARGETS[@]}"; do
  _bn="$(basename "$_h")"
  _line2="$(sed -n '2p' "$_h")"
  if printf '%s' "$_line2" | grep -q '^# zskills-hook-version:[[:space:]]*[0-9]'; then
    pass "hook $_bn carries line-2 # zskills-hook-version: stamp"
  else
    fail "hook $_bn carries line-2 # zskills-hook-version: stamp" "expected '# zskills-hook-version: <ver>' on line 2, got: $_line2"
  fi
done

echo ""
echo "=== weak-skill static invariants — qe-audit / session-report ==="
# SKILL_VERIFICATION_SMOKES Phase 3: the LLM-judgment-bound skills have no
# executable behavioral surface a shell smoke can drive — their only
# deterministic property is static SKILL.md structure. Guard the documented
# modes / formats / rules against accidental deletion with thin static greps.
# (Per the plan's grep-first rule, assertions that duplicate an existing
# conformance check are SKIPPED and recorded in the phase notes; e.g.
# qe-audit's `## Files to change` is already asserted at the #681 section
# above, so it is NOT re-asserted here.)

# qe-audit — meta-command precedence prose (stop/next/now). The
# `## Files to change` issue-body requirement is ALREADY covered at the
# #681 section above (check qe-audit "issue body format prescribes
# Files-to-change") — not duplicated here.
check_fixed qe-audit "meta-command 'Takes precedence' prose" 'Takes precedence'
check_fixed qe-audit "meta-command: stop (highest precedence)" 'stop'
check_fixed qe-audit "meta-command: next"                     'next'

# session-report — report-format template structure + no-bulk-scans rule.
check_fixed session-report "report template header"   '## Session Report — <date> <time> ET'
check_fixed session-report "report template Headline:" '**Headline:**'
check_fixed session-report "report template Intent → status:" '**Intent → status:**'
check_fixed session-report "report template Next action:" '**Next action:**'
check_fixed session-report "no-bulk-scans prohibition"  'Do not run bulk repo scans'

# ── #976 — agents must not recommend /land-pr (or any user-invocable:false
#    skill) as a user-typeable next step. Catches the regression in skill
#    SOURCE files only — agent chat output is not source-gated by this test;
#    the rules in CLAUDE_TEMPLATE.md + land-pr/SKILL.md cover the runtime side.
# ---------------------------------------------------------------------------
echo "── #976 — no user-typed-recommendation of user-invocable:false skills ──"

# Discover the current set of user-invocable:false skills (schema-driven).
USER_INVOCABLE_FALSE_SKILLS=()
while IFS= read -r f; do
  slug=$(basename "$(dirname "$f")")
  USER_INVOCABLE_FALSE_SKILLS+=("$slug")
done < <(grep -l '^user-invocable: false$' "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null || true)

if [ "${#USER_INVOCABLE_FALSE_SKILLS[@]}" -eq 0 ]; then
  pass "#976: no user-invocable:false skills present in skills/ — assertion vacuous"
else
  # Antipattern verbs that read as user-typing instructions.
  # (We deliberately omit "run", "dispatch", and "invoke" — they false-
  # positive on legitimate prose like "/run-plan dispatches /land-pr
  # internally" and "callers invoke /land-pr via the Skill tool". The
  # narrow set "type" / "re-run" reliably reads as a human-typing
  # recommendation in agent-report context.)
  for slug in "${USER_INVOCABLE_FALSE_SKILLS[@]}"; do
    HITS=$(grep -rEn "(^|[^a-zA-Z\`])(type|re-run)[[:space:]]+\`?/$slug\b" \
      --include='*.md' \
      "$REPO_ROOT"/skills/ 2>/dev/null \
      | grep -vE "skills/$slug/SKILL.md.*user-invocable|references/.*self-defense|test-skill-conformance" \
      || true)
    if [ -z "$HITS" ]; then
      pass "#976: no user-typed-recommendation of /$slug in skill bodies"
    else
      fail "#976: skill bodies contain user-typed-recommendation of /$slug" "(type|re-run) /$slug"
      echo "$HITS" | sed 's/^/        /'
    fi
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
