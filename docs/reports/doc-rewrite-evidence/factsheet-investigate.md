# Factsheet — `docs/skills/investigate.md`

Each doc claim is paired with the verbatim source line that supports it. Source
of truth: `skills/investigate/SKILL.md` (current HEAD). Companion claims are
additionally cited to `COMPANIONS.md`. Verifier checks these mechanically.

---

## What it does

**Doc:** "`/investigate` takes one bug whose cause is unclear and works it end to end: it reproduces the bug, traces the failure back to its source, states the root cause in writing, applies a minimal fix, and verifies that fix."
- `skills/investigate/SKILL.md:6-8`: "Disciplined workflow: reproduce, trace, state root cause, fix, verify. The agent must PROVE root-cause understanding before writing a fix."
- `skills/investigate/SKILL.md:16-17`: "Enforces discipline: you must SEE the bug, TRACE the cause, EXPLAIN it, then fix it. No guessing."

**Doc:** "no fix may be written until the root cause has been proven … the natural instinct is to skip straight to 'try a fix,' and every step here is built to prevent that."
- `skills/investigate/SKILL.md:19-21`: "This skill exists because agents naturally skip straight to \"try a fix.\" Every phase gate here is designed to prevent that. You may not write a fix until Phase 3 is complete."

**Doc:** "It is for a single bug, not a backlog. If you want to work through several issues, that is `/fix-issues`, not `/investigate` — the skill will redirect you."
- `skills/investigate/SKILL.md:23-25`: "**One bug at a time.** This is not `/fix-issues`. If the user wants batch fixing, redirect them there."

**Doc:** "`/investigate` is the right tool when the cause is genuinely unclear and guessing has already failed or would waste time."
- `skills/investigate/SKILL.md:25-26`: "`/investigate` is for the bug where the cause is unclear and guessing has failed or would waste time."

### Reproduce

**Doc:** "See the bug with your own eyes — observe it, don't just read about it."
- `skills/investigate/SKILL.md:52`: "**Goal:** See the bug with your own eyes. Not \"read about it\" — observe it."

**Doc:** "driving the UI with `playwright-cli` and taking a screenshot, writing a minimal failing test, capturing a stack trace, or running the specific failing test."
- `skills/investigate/SKILL.md:102`: "| UI/visual | `playwright-cli` — navigate, interact, screenshot |"
- `skills/investigate/SKILL.md:103`: "| Logic/computation | Write a minimal failing test in `/tmp/investigate-repro.test.js` |"
- `skills/investigate/SKILL.md:104`: "| Crash/error | Find the stack trace (test output, browser console, error log) |"
- `skills/investigate/SKILL.md:105`: "| Test failure | Run the specific test: `node --test tests/<file>.test.js` |"

**Doc:** "The reproduction (screenshot, test output, or error message) is recorded as evidence."
- `skills/investigate/SKILL.md:107-110`: "**Record reproduction evidence:** - Screenshot (UI bugs) … - Test output showing the failure (logic bugs) - Stack trace or error message (crashes)"

**Doc:** "If the bug genuinely can't be reproduced (for example, a non-deterministic race, or something that needs a specific browser or OS), the investigation may continue with an explicit note that it is lower-confidence"
- `skills/investigate/SKILL.md:112-113`: "**Gate:** If you cannot reproduce the bug after genuine attempts, you may proceed with an explicit skip:"
- `skills/investigate/SKILL.md:120-121`: "Valid reasons: \"race condition, not deterministic\", \"requires specific browser/OS\" …"
- `skills/investigate/SKILL.md:125`: "If you skip, flag the investigation as lower confidence in the report."

**Doc:** "'I can see it in the code' or 'reproducing would take too long' are not acceptable reasons to skip."
- `skills/investigate/SKILL.md:122-123`: "Invalid reasons: \"I can see the bug in the code\" (that's tracing, not reproducing), \"reproduction would take too long\" (then you're guessing)."

### Trace

**Doc:** "Follow the code from the symptom backward — which function produced the wrong value, what called it, where its arguments came from — until you reach the first place something actually goes wrong."
- `skills/investigate/SKILL.md:138-143`: "**Follow the call chain.** From the symptom, trace backward: - What function produced the wrong output? - What called that function? With what arguments? - Where did those arguments come from? - Keep going until you reach the ROOT — the first place where something goes wrong."

**Doc:** "uses `Grep` to find call sites and `Read` to inspect the real code rather than working from memory"
- `skills/investigate/SKILL.md:146`: "- `Grep` to find all call sites of the broken function"
- `skills/investigate/SKILL.md:147`: "- `Read` to examine the actual code (not from memory)"

**Doc:** "consults git history (`git show`, never `git checkout`, so the working tree is left untouched) when a regression is suspected"
- `skills/investigate/SKILL.md:148`: "- `git log --oneline -10 -- <file>` if you suspect a regression"
- `skills/investigate/SKILL.md:151`: "- **Never** `git checkout` old commits to investigate — use `git show`"

**Doc:** "The output is a stated causal chain: A calls B with X, B passes X to C, C breaks on X because of Y."
- `skills/investigate/SKILL.md:153-156`: "**Build the causal chain.** You must be able to state it as: > \"A calls B with argument X. B passes X to C. C assumes X is non-null but X is null because A doesn't check for the empty-array case …\""

### Root cause

**Doc:** "Write the diagnosis down before touching any code: what's broken and where, the observed evidence that proves it (not a guess …), the causal chain, why existing tests didn't catch it, and what the fix will change."
- `skills/investigate/SKILL.md:168`: "**Goal:** Prove you understand the bug before touching any code."
- `skills/investigate/SKILL.md:176-188`: root-cause statement sections "**What's broken:**", "**Evidence:** <… not a guess, something you observed>", "**Location:** <file:line>", "**Why it's broken:**", "**Why it wasn't caught:**", "**Fix approach:**".

**Doc:** "When you run `/investigate` yourself, it pauses here to show you the root-cause statement and wait for your confirmation before going further, in case you have context that changes the analysis."
- `skills/investigate/SKILL.md:197-199`: "**Gate:** In interactive mode (no `auto` flag from a parent skill), present the root cause statement to the user and wait for confirmation before proceeding. The user may have context that changes the analysis."

### Fix

**Doc:** "Write the regression test first and confirm it fails — a test that passes without the fix proves nothing."
- `skills/investigate/SKILL.md:209-213`: "**Write the regression test FIRST.** … Run it — it MUST FAIL. If it passes, your test doesn't capture the bug. Rewrite it."

**Doc:** "change the minimum code needed to address the root cause, with no refactoring of nearby code and no fixing of other bugs noticed along the way (those get filed as separate issues)."
- `skills/investigate/SKILL.md:216-221`: "**Apply the fix.** Change the minimum code necessary: … - Do not refactor surrounding code … - Do not fix other bugs you noticed during tracing (file separate issues for those)"

**Doc:** "Run the test again; it must now pass."
- `skills/investigate/SKILL.md:223`: "**Run the regression test again.** It MUST PASS now."

**Doc:** "If the fix fails twice, the skill stops and reports what it tried rather than guessing a third time."
- `skills/investigate/SKILL.md:226-231`: "**Two-attempt limit.** If your fix fails twice … STOP. Report: … Do not guess a third time."

### Verify

**Doc:** "Confirm the regression test passes, re-run the original reproduction to confirm the bug is gone, and run the full test suite."
- `skills/investigate/SKILL.md:240`: "**Run the regression test** — confirm it passes …"
- `skills/investigate/SKILL.md:242-244`: "**Reproduce the original bug scenario** — repeat Phase 1 reproduction steps. Confirm the bug is gone"
- `skills/investigate/SKILL.md:249`: "**Run the full test suite:**"

**Doc:** "If the fix touched shared code, it checks other callers for side effects."
- `skills/investigate/SKILL.md:272-275`: "**Check for side effects.** If the fix changed shared code (utility functions, base classes, model structures): - Grep for other callers of the modified function - Verify they still work correctly"

**Doc:** "A test that fails in code the fix didn't touch follows the project's pre-existing-failure protocol rather than being silently absorbed."
- `skills/investigate/SKILL.md:278-280`: "**If tests fail on code you didn't touch:** follow the pre-existing failure protocol from CLAUDE.md (verify with `git log`, file issue, skip with `#NNN` reference)."

### Deliverables / report

**Doc:** "The deliverables are the fix, the regression test, and an inline report — `/investigate` writes no persistent report file."
- `skills/investigate/SKILL.md:284`: "Output an inline report. No persistent report file."
- `skills/investigate/SKILL.md:361-362`: "**No persistent report file.** The fix, the regression test, and the inline report are the deliverables."

**Doc:** "The report lays out the reproduction, the root cause, what changed, and the verification results."
- `skills/investigate/SKILL.md:307-328`: report template with "### Reproduction", "### Root Cause", "### Fix", "### Verification".

**Doc:** "If the investigation is abandoned (couldn't reproduce, couldn't find the cause, or the fix failed twice), it reports what was learned and what remains unknown instead."
- `skills/investigate/SKILL.md:330-331`: "If the investigation was abandoned (couldn't reproduce, couldn't find root cause, fix failed twice), report what was learned and what remains unknown."

---

## Typical usage

**Doc:** "Point `/investigate` at one bug — either a GitHub issue number or a plain description of the symptom" + the three examples.
- `skills/investigate/SKILL.md:45-48`: "Examples: - `/investigate #387` — investigate GitHub issue 387 - `/investigate Scope block shows NaN after 10 seconds of simulation` - `/investigate test failure in tests/blocks/pid.test.js \"derivative term\"`"

**Doc:** "When you give it an issue number, `/investigate` fetches that issue with `gh issue view` and reads the full body and comments — not just the title — as its starting point."
- `skills/investigate/SKILL.md:40-42`: "`#123` — fetch the GitHub issue with `gh issue view 123` and use its title, body, and comments as the starting point"
- `skills/investigate/SKILL.md:54-56`: "Read the full body and comments — not just the title"

**Doc:** "(Reading only the title has burned past investigations: issue #387's 'reset button' was misread as 'clear the canvas' when the body said 'reset mappings to defaults.')"
- `skills/investigate/SKILL.md:56-58`: "(past failure: #387 \"reset button\" was interpreted as \"clear canvas\" instead of \"reset mappings to defaults\" because only the title was read)."

**Doc:** "A plain description starts from the symptom you describe: an error message, a wrong-output behavior, or a specific failing test."
- `skills/investigate/SKILL.md:43-44`: "Free text — describes the bug to investigate (error message, behavior, failing test name, etc.)"

**Doc:** "When the input is an issue number, `/investigate` also claims that issue first, so a parallel `/fix-issues` run (or another `/investigate`) won't work the same issue at the same time."
- `skills/investigate/SKILL.md:59-63`: "**Claim the issue (when the input IS an issue number).** … acquire the `claim-issue.sh` claim BEFORE any reproduction work — this prevents a concurrent `/fix-issues` cron (or another `/investigate`) from double-working the same issue."

**Doc:** "If the issue is already claimed by another run, `/investigate` declines and stops."
- `skills/investigate/SKILL.md:85`: "10) echo \"issue #$N is being worked by another pipeline; declining.\" >&2 ;;"
- `skills/investigate/SKILL.md:91-92`: "On `ACQ_RC` 10 / 11 / 2 → **STOP this invocation** … this is a one-shot skill, not a sprint loop"

**Doc:** "A plain-text description claims nothing, since there's no issue to claim."
- `skills/investigate/SKILL.md:63-65`: "**Skip this entirely for a bare-text description** (no issue number → nothing to claim)."

---

## Companion skills (cross-checked against COMPANIONS.md)

**Doc:** "`/fix-issues` — the batch counterpart. `/investigate` is for one bug at a time; for working through several issues, use `/fix-issues`, which will redirect you here when a single bug needs deeper digging."
- `skills/investigate/SKILL.md:23-25`: "**One bug at a time.** This is not `/fix-issues`. If the user wants batch fixing, redirect them there."
- `COMPANIONS.md:85`: "`investigate` | `fix-issues`, `create-worktree`, `update-zskills` | Proves a root cause; its fix then routes to `/quickfix` or `/do` (per CLAUDE.md)."

**Doc:** "When `/fix-issues` can't diagnose a bug within its normal flow (two failed attempts), it skips that issue with a note that it needs deeper investigation, and you then run `/investigate` on it. There is no automatic escalation — the hand-off is your decision."
- `skills/investigate/SKILL.md:28-32`: "**When `/fix-issues` should escalate here:** If a fix agent can't diagnose a bug within its normal flow (2 failed attempts), `/fix-issues` should skip that issue with a note: \"Needs deeper investigation …\" The user then runs `/investigate` on the flagged issue. No automatic escalation — the skill boundary is the user's decision."

**Doc:** "`/quickfix` and `/do` — where the fix goes once the root cause is known. `/quickfix` assumes the fix is already understood; `/investigate` is what you run first when it isn't. Once `/investigate` has proven the cause, the fix itself can be carried by `/quickfix` … or `/do` … Choose between those two by project policy."
- `COMPANIONS.md:58-60`: "**`/investigate` vs `/quickfix`**: `/quickfix` assumes the fix is known; `/investigate` proves the root cause first, then its fix may dispatch `/quickfix` or `/do`."
- `COMPANIONS.md:50-52` (quickfix vs do): "`/quickfix` does `git checkout -b` on main; `/do` uses a worktree. Pick by **project policy**: `main_protected: true` → `/do`; otherwise either."

---

## Arguments

**Doc:** "`/investigate` takes a single argument. Two forms are accepted" — `#N` (GitHub issue) and free text.
- `skills/investigate/SKILL.md:4` (frontmatter `argument-hint`): "<description or #issue>"
- `skills/investigate/SKILL.md:36-44`: "`/investigate <description or #issue>` … `#123` — fetch the GitHub issue … - Free text — describes the bug to investigate"

**Doc:** "The issue is fetched with `gh issue view`, and its title, body, and comments become the starting point. This form also triggers the issue claim described under Typical usage."
- `skills/investigate/SKILL.md:40-42`: "`#123` — fetch the GitHub issue with `gh issue view 123` and use its title, body, and comments as the starting point"
- `skills/investigate/SKILL.md:59-61`: "**Claim the issue (when the input IS an issue number).**"

---

## Tips & Gotchas (all drawn from Key Rules)

**Doc:** "One bug at a time — this is not `/fix-issues`."
- `skills/investigate/SKILL.md:23-24`: "**One bug at a time.** This is not `/fix-issues`."

**Doc:** "No fix before reproducing, and no fix before the root cause is stated."
- `skills/investigate/SKILL.md:342-346`: "**Never fix before reproducing.** … Phase 1 is not optional. **Never fix before stating root cause.** Writing code before Phase 3 is complete means you're guessing."

**Doc:** "The regression test must fail before the fix is applied. A test that passes without the fix doesn't capture the bug."
- `skills/investigate/SKILL.md:348-350`: "**Regression test must fail first.** A test that passes without the fix doesn't prove anything. Run it before applying the fix to confirm it captures the bug."

**Doc:** "The fix is minimal. Other bugs noticed while tracing are filed as separate issues, not folded into this fix."
- `skills/investigate/SKILL.md:351-353`: "**Minimal fix.** Change the least code possible. If you find other bugs during investigation, file them as separate issues — don't scope-creep the fix."

**Doc:** "Two attempts is the maximum. If the same test fails after two fix attempts, `/investigate` stops and reports rather than guessing again."
- `skills/investigate/SKILL.md:354-355`: "**Two-attempt maximum.** If the same test fails after two fix attempts, stop and report. You're guessing, not debugging."

**Doc:** "When stuck — flaky reproduction, unclear cause, or a fix with unexpected consequences — `/investigate` reports its findings and asks rather than fabricating an explanation. 'I don't know' is a valid answer."
- `skills/investigate/SKILL.md:363-365`: "**Ask when stuck.** If reproduction is flaky, root cause is unclear, or the fix has unexpected consequences — report your findings and ask the user. \"I don't know\" is a valid answer. Fabricating an explanation is not."
