---
name: investigate
disable-model-invocation: false
argument-hint: "<description or #issue>"
description: >-
  Deep debugging for one complex bug at a time. Disciplined workflow:
  reproduce, trace, state root cause, fix, verify. The agent must PROVE
  root-cause understanding before writing a fix.
metadata:
  version: "2026.06.03+e8151e"
---

# /investigate \<description or #issue> — Root-Cause Debugging

Systematic investigation of a single bug that's too complex for batch
fixing. Enforces discipline: you must SEE the bug, TRACE the cause,
EXPLAIN it, then fix it. No guessing.

**Ultrathink throughout.** This skill exists because agents naturally
skip straight to "try a fix." Every phase gate here is designed to
prevent that. You may not write a fix until Phase 3 is complete.

**One bug at a time.** This is not `/fix-issues`. If the user wants
batch fixing, redirect them there. `/investigate` is for the bug where
the cause is unclear and guessing has failed or would waste time.

**When `/fix-issues` should escalate here:** If a fix agent can't
diagnose a bug within its normal flow (2 failed attempts), `/fix-issues`
should skip that issue with a note: "Needs deeper investigation — could
not determine root cause in batch mode." The user then runs `/investigate`
on the flagged issue. No automatic escalation — the skill boundary is
the user's decision.

## Arguments

```
/investigate <description or #issue>
```

- `#123` — fetch the GitHub issue with `gh issue view 123` and use its
  title, body, and comments as the starting point
- Free text — describes the bug to investigate (error message, behavior,
  failing test name, etc.)

Examples:
- `/investigate #387` — investigate GitHub issue 387
- `/investigate Scope block shows NaN after 10 seconds of simulation`
- `/investigate test failure in tests/blocks/pid.test.js "derivative term"`

## Phase 1 — Reproduce

**Goal:** See the bug with your own eyes. Not "read about it" — observe it.

1. **Parse the input.** If `#N`, fetch the issue. Read the full body and
   comments — not just the title (past failure: #387 "reset button" was
   interpreted as "clear canvas" instead of "reset mappings to defaults"
   because only the title was read).

   **Claim the issue (when the input IS an issue number).** `/investigate`
   has no pipeline id of its own, so synthesize one and acquire the
   `claim-issue.sh` claim BEFORE any reproduction work — this prevents a
   concurrent `/fix-issues` cron (or another `/investigate`) from
   double-working the same issue. **Skip this entirely for a bare-text
   description** (no issue number → nothing to claim). Extract the bare
   positive integer (strip a leading `#` and any quotes) into `$N` and
   synthesize the pipeline id through the shared sanitizer:

   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   # Only when the input is an issue reference. $N = bare positive integer
   # (claim-issue.sh rejects non-numeric / decorated input with exit 2).
   N="${N#\#}"          # strip a leading '#'
   N="${N//\"/}"        # strip any quotes
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "investigate.issue-$N")
   CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
   bash "$CLAIM_HELPER" acquire "$N" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"
   ACQ_RC=$?
   case "$ACQ_RC" in
     0)  : ;;  # acquired (fresh or self-re-entry) — proceed
     10) echo "issue #$N is being worked by another pipeline; declining." >&2 ;;
     11) echo "claim-issue.sh: filesystem error acquiring issue #$N; stopping." >&2 ;;
     2)  echo "claim-issue.sh: usage error (empty PIPELINE_ID or non-numeric N=$N) — internal bug; stopping." >&2 ;;
   esac
   ```

   On `ACQ_RC` 10 / 11 / 2 → **STOP this invocation** (print the message
   above and do not proceed — this is a one-shot skill, not a sprint loop).
   On `ACQ_RC=0` continue. The claim is released on every terminal path
   below (success-path bash block at the Report, and the explicit per-STOP
   release prose at each abandon point).

2. **Reproduce the bug** based on its type:

   | Bug type | How to reproduce |
   |----------|-----------------|
   | UI/visual | `playwright-cli` — navigate, interact, screenshot |
   | Logic/computation | Write a minimal failing test in `/tmp/investigate-repro.test.js` |
   | Crash/error | Find the stack trace (test output, browser console, error log) |
   | Test failure | Run the specific test: `node --test tests/<file>.test.js` |
   | Race condition | Reproduce with timing (setTimeout, rapid clicks, concurrent ops) |

3. **Record reproduction evidence:**
   - Screenshot (UI bugs) — save to `.playwright/output/`
   - Test output showing the failure (logic bugs)
   - Stack trace or error message (crashes)

4. **Gate:** If you cannot reproduce the bug after genuine attempts, you
   may proceed with an explicit skip:

   ```
   REPRODUCTION: SKIP — <reason>
   ```

   Valid reasons: "race condition, not deterministic", "requires specific
   browser/OS", "timing-dependent, identified likely cause by code reading."

   Invalid reasons: "I can see the bug in the code" (that's tracing, not
   reproducing), "reproduction would take too long" (then you're guessing).

   If you skip, flag the investigation as lower confidence in the report.
   (This is not an abandon — you proceed. The claim is held until the
   terminal Report releases it.)

## Phase 2 — Trace

**Goal:** Find the exact line and condition that causes the failure. Follow
the code, don't guess.

1. **Start from the symptom.** Read the error message or incorrect output
   carefully. What value is wrong? What's null that shouldn't be? What
   event didn't fire?

2. **Follow the call chain.** From the symptom, trace backward:
   - What function produced the wrong output?
   - What called that function? With what arguments?
   - Where did those arguments come from?
   - Keep going until you reach the ROOT — the first place where something
     goes wrong.

3. **Use targeted tools:**
   - `Grep` to find all call sites of the broken function
   - `Read` to examine the actual code (not from memory)
   - `git log --oneline -10 -- <file>` if you suspect a regression
   - `git show <commit>:<file>` to compare with a known-good version
   - Add `console.log` via playwright-cli `eval` if you need runtime values
   - **Never** `git checkout` old commits to investigate — use `git show`

4. **Build the causal chain.** You must be able to state it as:
   > "A calls B with argument X. B passes X to C. C assumes X is non-null
   > but X is null because A doesn't check for the empty-array case in
   > line 47 of src/foo.js."

   If you can't state this chain, you haven't found the root cause yet.
   Keep tracing.

5. **Check for related issues.** Once you find the root cause:
   - Is the same pattern used elsewhere? (Same bug in other places?)
   - Are there existing tests that should have caught this?
   - Was this introduced by a specific commit? (`git log --oneline -20 -- <file>`)

## Phase 3 — Root Cause Statement

**Goal:** Prove you understand the bug before touching any code. This is
the key discipline gate.

Write a root cause statement with exactly these sections:

```
### Root Cause

**What's broken:** <specific function/line>
**Evidence:** <the specific output, error, or test result that proves this
is the cause — not a guess, something you observed>
**Location:** <file:line>

**Why it's broken:** <the causal chain from Phase 2 — A calls B, B does X,
but X fails when Y because Z>

**Why it wasn't caught:** <missing test? edge case not considered? race
condition? silent failure?>

**Fix approach:** <what specifically will change — which file, which
function, what the fix does>
```

The **Evidence** field is critical. If you can't point to specific output
that proves your diagnosis, you're guessing. "The sort function probably
doesn't handle nulls" is a guess. "Line 312 receives `undefined` for
`stepSize` as shown by the test output 'TypeError: Cannot read properties
of undefined'" is evidence.

**Gate:** In interactive mode (no `auto` flag from a parent skill), present
the root cause statement to the user and wait for confirmation before
proceeding. The user may have context that changes the analysis.

If running autonomously (dispatched by another skill), proceed directly
to Phase 4 — but the root cause statement must still be written and
included in the final report.

## Phase 4 — Fix

**Goal:** Targeted fix based on the root cause. Fix the bug, not the world.

1. **Write the regression test FIRST.** Before changing any source code:
   - Add a test case to the appropriate test file in `tests/`
   - The test must exercise the exact scenario from Phase 1
   - Run it — it MUST FAIL. If it passes, your test doesn't capture the
     bug. Rewrite it.
   - Save the failing output as evidence.

2. **Apply the fix.** Change the minimum code necessary:
   - Fix the specific issue identified in Phase 3
   - Do not refactor surrounding code
   - Do not "improve" adjacent functions
   - Do not fix other bugs you noticed during tracing (file separate
     issues for those)

3. **Run the regression test again.** It MUST PASS now. If it doesn't,
   your fix is wrong — go back to Phase 2 and re-trace.

4. **Two-attempt limit.** If your fix fails twice (test still fails after
   two different fix attempts), STOP. Report:
   - What you tried both times
   - Why each attempt failed
   - What you think is actually happening
   Let the user decide the next step. Do not guess a third time.
   **Before stopping, release the issue claim** (only if you acquired one
   in Phase 1 — i.e. the input was an issue number):
   `bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$N" --require-pipeline "$PIPELINE_ID"`.

## Phase 5 — Verify

**Goal:** Prove the fix works and doesn't break anything else.

1. **Run the regression test** — confirm it passes (should already pass
   from Phase 4 step 3).

2. **Reproduce the original bug scenario** — repeat Phase 1 reproduction
   steps. Confirm the bug is gone:
   - UI: take a new screenshot, compare with the Phase 1 screenshot
   - Logic: run the same test/scenario that failed before
   - Crash: confirm no error in the same conditions

3. **Run the full test suite:**
   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   if [ -z "$FULL_TEST_CMD" ]; then
     echo "ERROR: testing.full_cmd not configured. Run /update-zskills." >&2
     # Release the issue claim before bailing (only if one was acquired
     # in Phase 1 — i.e. the input was an issue number; $N / $PIPELINE_ID
     # are set there and survive in the persistent shell).
     if [ -n "${N:-}" ] && [ -n "${PIPELINE_ID:-}" ]; then
       bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$N" --require-pipeline "$PIPELINE_ID"
     fi
     exit 1
   fi
   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   mkdir -p "$TEST_OUT"
   $FULL_TEST_CMD > "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" 2>&1
   ```
   Read `"$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}"` to check results. All suites must pass.

4. **Check for side effects.** If the fix changed shared code (utility
   functions, base classes, model structures):
   - Grep for other callers of the modified function
   - Verify they still work correctly
   - Run any related test files individually if concerned

5. **If tests fail on code you didn't touch:** follow the pre-existing
   failure protocol from CLAUDE.md (verify with `git log`, file issue,
   skip with `#NNN` reference).

## Report

Output an inline report. No persistent report file.

**Release the issue claim (success path).** When the input was an issue
number (Phase 1 acquired a claim), release it now that the investigation
has reached its terminal Report — the work is resolved, the claim should
not persist. Skip when the input was a bare description (no claim was
acquired):

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# $N and $PIPELINE_ID were set in Phase 1 step 1 (issue-number path only)
# and survive in the persistent shell. The release is ownership-safe
# (--require-pipeline refuses to release a claim another pipeline owns).
if [ -n "${N:-}" ] && [ -n "${PIPELINE_ID:-}" ]; then
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$N" --require-pipeline "$PIPELINE_ID"
fi
```

```
## Investigation: <title>

### Reproduction
<What was observed — error message, screenshot reference, or test output>

### Root Cause
**What's broken:** <specific function/line>
**Evidence:** <observed proof — error output, test result, screenshot>
**Why it's broken:** <causal chain>
**Why it wasn't caught:** <gap>

### Fix
**Changed:** <file(s) and what changed>
**Regression test:** <test file and test name>
**Test asserts:** <what specific value/behavior the test checks>
**Catches the bug because:** <why this assertion would have failed before the fix>

### Verification
- Regression test: PASS
- Original scenario: PASS (bug no longer reproduces)
- Full test suite: <command + per-suite results>
```

If the investigation was abandoned (couldn't reproduce, couldn't find root
cause, fix failed twice), report what was learned and what remains unknown.
**Before stopping on any abandon path, release the issue claim** (only if
the input was an issue number and Phase 1 acquired a claim):
`bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$N" --require-pipeline "$PIPELINE_ID"`.
This covers the couldn't-reproduce STOP (Phase 1), the couldn't-find-root
STOP (Phase 2/3 — when you cannot state the causal chain), and the
two-attempt-limit STOP (Phase 4). A released claim lets the next pipeline
pick up the issue cleanly.

## Key Rules

- **Never fix before reproducing.** You must SEE the bug. Reading a
  description is not seeing it. Phase 1 is not optional.
- **Never fix before stating root cause.** Writing code before Phase 3
  is complete means you're guessing. Guessing is what `/investigate`
  exists to prevent.
- **Never weaken tests.** Fix the code, not the test.
- **Regression test must fail first.** A test that passes without the fix
  doesn't prove anything. Run it before applying the fix to confirm it
  captures the bug.
- **Minimal fix.** Change the least code possible. If you find other bugs
  during investigation, file them as separate issues — don't scope-creep
  the fix.
- **Two-attempt maximum.** If the same test fails after two fix attempts,
  stop and report. You're guessing, not debugging.
- **Never modify the working tree to check pre-existing failures.** If
  you touched code and tests fail, fix them.
- **Read the full issue body.** Not just the title. Past failure: #387.
- **Use `git show`, not `git checkout`, for investigation.** Never check
  out old commits to compare — it modifies the working tree.
- **No persistent report file.** The fix, the regression test, and the
  inline report are the deliverables. No `$ZSKILLS_AUDIT_DIR/investigate-*.md`.
- **Ask when stuck.** If reproduction is flaky, root cause is unclear, or
  the fix has unexpected consequences — report your findings and ask the
  user. "I don't know" is a valid answer. Fabricating an explanation is not.
