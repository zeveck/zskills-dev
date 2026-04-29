---
name: investigate
disable-model-invocation: false
argument-hint: "<description or #issue>"
description: >-
  Deep debugging for complex bugs. Enforces a disciplined workflow:
  reproduce, trace, state root cause, fix, verify. The agent must PROVE
  it understands the root cause before writing any fix.
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
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   if [ -z "$FULL_TEST_CMD" ]; then
     echo "ERROR: testing.full_cmd not configured. Run /update-zskills." >&2
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
  inline report are the deliverables. No `reports/investigate-*.md`.
- **Ask when stuck.** If reproduction is flaky, root cause is unclear, or
  the fix has unexpected consequences — report your findings and ask the
  user. "I don't know" is a valid answer. Fabricating an explanation is not.
