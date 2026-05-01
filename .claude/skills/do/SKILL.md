---
name: do
disable-model-invocation: true
argument-hint: "<description> [worktree] [push] [pr] [every SCHEDULE] [now] [--force] [--rounds N] | stop [query] | next [query] | now [query]"
description: >-
  Lightweight task dispatcher for ad-hoc work: documentation, examples,
  refactoring, content updates. Supports scheduling with every/now/next/stop.
  Usage: /do <description> [worktree] [push] [pr] [every SCHEDULE] [now] [--force] [--rounds N] | stop | next.
---

# /do \<description> [worktree] [push] [pr] [every SCHEDULE] [--force] [--rounds N] | stop [query] | next [query] | now [query] — Lightweight Task Dispatcher

Execute small, ad-hoc tasks with structured research, verification, and
optional isolation or auto-push. Can be scheduled for recurring maintenance
tasks. For work that doesn't warrant the full ceremony of `/run-plan` (plan
phases) or `/fix-issues` (batch bug fixing).

**Ultrathink throughout.**

## When to Use `/do`

| Task | Use |
|------|-----|
| Documentation, examples, presentations, screenshots | `/do` |
| Small refactors, one-off fixes, content updates | `/do` |
| Adding a new block type | `/add-block` (10-step workflow) |
| Newsletter entry | `/do` or `/doc newsletter` |
| Batch bug fixing (N issues) | `/fix-issues N` |
| Executing a plan phase | `/run-plan` |
| Multi-file feature work with dependencies | `/run-plan` |

**Rule of thumb:** if the task needs a worktree, separate verification agent,
and a persistent report file, it's too big for `/do`. Use `/run-plan` instead.

## Arguments

```
/do <description> [worktree|direct|pr] [push] [every SCHEDULE] [now]
/do stop | next
```

- **description** (required) — what to do, in natural language
- **landing flags** (optional, mutually exclusive) — override the
  `execution.landing` default in `.claude/zskills-config.json`:
  - **worktree** — isolate in `/tmp/<project>-do-<slug>/`, cherry-pick
    back to main after verification. Matches `execution.landing: "cherry-pick"`.
  - **pr** — named worktree + feature branch, push, create PR to main,
    poll CI. Matches `execution.landing: "pr"`.
  - **direct** — work on main in place, no landing step. Matches
    `execution.landing: "direct"`.
  - When no flag is given, read `execution.landing` from config.
    (`cherry-pick` → worktree, `pr` → pr, `direct` → direct, missing
    config → direct.)
- **push** (optional) — auto-push to remote after verification passes.
  Upgrades verification to use a **separate verification agent** running
  `/verify-changes`. Push never happens without verification passing
  first. Ignored in `pr` mode (PR mode handles push internally).
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior.
- **--force** (optional) — bypass triage redirect and review reject. Persists
  into the cron prompt verbatim when used with `every`.
- **--rounds N** (optional) — max review/refine cycles (default 1; `0` skips
  review with stderr WARN).
- **stop** — cancel `/do` cron(s). Bare `/do stop` → all crons.
  With query `/do stop Check docs` → targets matching cron.
- **next** — check next fire time. Bare → all. With query → targeted.

**Detection:** If `$ARGUMENTS` starts with a quoted string (`"..."`),
the quoted text is the description — skip meta-command detection entirely.
This lets users escape edge cases like `/do "Now fix the tooltip bug"`.

Otherwise, check the **first word** of `$ARGUMENTS`:
- `stop [query]` — meta-command: cancel crons. Bare → all. With query → targeted.
- `next [query]` — meta-command: show fire times. Bare → all. With query → targeted.
- `now [query]` — meta-command: trigger immediately. Bare → all/ask. With query → targeted.

Meta-commands (`stop`, `next`, `now`) bypass Phase 0a triage and Phase 0b review entirely. They are administrative — there is no description to evaluate.

If the first word is NOT a meta-command, it's a regular task. Parse
trailing flags from the END backward:
- `push` — recognized at the end
- `worktree` — recognized at the end (landing flag)
- `direct` — recognized at the end (landing flag)
- `pr` — recognized at the end (landing flag; use extended pattern with `.!?` punctuation, since task descriptions are prose-like and "pr" may appear as "PR." at end of sentence)
- `every <schedule>` — recognized at the end (e.g., `every 4h`, `every day at 9am`)
- `now` — recognized at the end (only meaningful with `every`: run now AND schedule)

**Landing-flag detection** — resolves to `LANDING_MODE ∈ {pr, worktree, direct}`.
Explicit flag wins; otherwise fall back to `execution.landing` in
`.claude/zskills-config.json`; otherwise default `direct`. See Phase 1.5
for the full resolution block.

Everything before the trailing flags is the task description.

This means:
- `/do stop` — stop all `/do` crons
- `/do stop Check docs` — stop the "Check docs" cron
- `/do next` — show all fire times
- `/do next Check docs` — show fire time for "Check docs"
- `/do now` — trigger (if one) or ask (if multiple)
- `/do now Check docs` — trigger the "Check docs" cron
- `/do Push the latest changes` — description only, no flags
- `/do Update the presentation push` — description + push flag
- `/do Fix the tooltip bug worktree push` — description + both flags
- `/do Check docs every day at 9am` — schedule "Check docs" daily
- `/do Add dark mode. pr` — description + pr flag (PR mode)

Examples:
- `/do Add example models for Integrator and Derivative blocks`
- `/do Sort the screenshots in session-sequence-snapshots`
- `/do Refactor color constants in main.css worktree`
- `/do Update the presentation with Phase 3 results push`
- `/do Make sure docs are up to date every day at 9am`
- `/do Check for broken links in examples every 12h now`
- `/do Add dark mode to editor pr`
- `/do next` — all scheduled tasks
- `/do next Check docs` — specific task
- `/do stop` — cancel all
- `/do stop Check docs` — cancel specific task

## Meta-Commands: stop / next / now

These commands query or control `/do` crons. They work in two modes:

- **Bare** (`/do stop`, `/do next`, `/do now`) — applies to ALL `/do` crons
- **Targeted** (`/do stop Check docs`, `/do next Check docs`) — applies to the matching cron

### Cron Matching (for targeted commands)

When a description is present with `stop`/`next`/`now`, find the matching
cron by comparing the description against all `/do` cron prompts:

1. `CronList` → find all whose prompt starts with `Run /do`
2. Extract each cron's task description (strip `Run /do ` prefix and
   trailing flags)
3. **Fuzzy match:** check if the user's description words appear in the
   cron's description (case-insensitive, order-independent). E.g.,
   "Check docs" matches "Make sure docs are up to date" because both
   key words overlap. The user won't have tons of similar `/do` crons,
   so loose matching is fine.
4. **One match** → act on it. **Multiple matches** → list them, ask
   which one. **No matches** → report "no matching /do cron found."

### Now

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **One cron:** extract prompt, **run immediately.** Cron stays active.
3. **Multiple (bare only):** list them, ask which to trigger.
4. **None:** report `No active /do cron to trigger.` and **exit.**

### Next

1. `CronList` → find `/do` crons (all, or matching if description given)
2. For each, parse the cron expression and compute the next fire time.
   Use `TZ=America/New_York date` for the timezone. Show both relative
   and absolute:
   > Active /do crons:
   > 1. ~14h 47m (~9:03 AM ET tomorrow, cron XXXX)
   >    Prompt: Run /do Make sure docs are up to date every day at 9am now
   > 2. ~3h 12m (~8:15 PM ET, cron YYYY)
   >    Prompt: Run /do Check broken links every 4h now
3. **None:** `No active /do cron in this session.`
4. **Exit.**

### Stop

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **Bare with one cron:** delete it. Report what was cancelled.
3. **Bare with multiple:** list them, ask which to cancel (or "all").
4. **Targeted:** delete the matched cron. Report what was cancelled.
5. **None:** report "no active /do cron found."
6. **Exit.**

## Pre-flight — Flag pre-parse (runs before Phase 0a/0b/0c)

Phase 0a (triage) and Phase 0b (review) need to know `--force` and
`--rounds N`; Phase 0c (cron registration) needs them so the cron prompt
template can include them verbatim. Phase 1.5's argument parser runs AFTER
Phase 0c today, so this pre-parse runs first — at the very top of the
skill, before Phase 0a. This pre-parse is non-destructive: it sets `FORCE`
and `ROUNDS` shell variables but does NOT mutate `$ARGUMENTS` (Phase 1.5's
parser remains source of truth for the canonical strip).

```bash
# Pre-flight (runs before Phase 0a/0b/0c): read --force and --rounds N out
# of $ARGUMENTS so Phase 0c's cron prompt template can include them, and
# Phase 0a/0b can branch on them. Does not mutate $ARGUMENTS.

# Entry-point unset guard (WI 2a.3 test seam) — keep first so any code path
# that later reads _ZSKILLS_TEST_* env vars (triage, review, cron-prompt
# construction) sees the production-cleared values when the harness flag
# is absent. Symmetric to /quickfix WI 1a.3a.
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi

FORCE=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--force($|[[:space:]]) ]]; then
  FORCE=1
fi
ROUNDS=1
# Greedy-fallthrough: only consume `--rounds <N>` when N is a numeric literal.
# `/do fix the bug --rounds in production` would otherwise capture "in" as
# ROUNDS_RAW and exit 2, rejecting a legitimate description. The regex
# captures only when the trailing token is all-digits; non-numeric trailing
# tokens leave ROUNDS at default 1 and the literal `--rounds` remains as
# task-description prose (Phase 1.5's strip chain MUST NOT strip
# non-numeric `--rounds` matches — see WI 2a.4).
if [[ "$ARGUMENTS" =~ (^|[[:space:]])--rounds[[:space:]]+([0-9]+)($|[[:space:]]) ]]; then
  ROUNDS="${BASH_REMATCH[2]}"
fi
# Strict explicit-error case: `--rounds` followed by a clearly-non-numeric
# token that LOOKS like an intended integer arg (e.g. `--rounds 3.5` or
# `--rounds -1`) should still fail loudly rather than silent-ignore. The
# `^[0-9]+$` anchor catches `3.5` (matches only "3" not the full token, so
# the broader regex above won't match because BASH_REMATCH[2] is bounded by
# `[0-9]+` and the trailing `($|[[:space:]])` anchors require whitespace
# AFTER the digit run — if the token continues with `.5`, this is non-match
# and falls through to user-prose treatment. Same for `-1`. So `3.5` and
# `-1` both end up as user prose, which is the conservative default.
```

Validation: `fix tooltip --force --rounds 3 pr` strips to `fix tooltip` after
the full chain. `fix the bug --rounds in production` keeps the full
description (no strip), ROUNDS stays at 1.

## Phase 0a — Triage

Before any cron registration, fresh-agent review, or task work, the model
runs a triage gate to decide whether `/do` is the right skill for this
description. **Phase 0a runs BEFORE Phase 0c (cron registration).** A
REDIRECT path exits before any `CronCreate` call, so a redirected `/do`
leaves no cron behind. Phase 0c cannot run on a redirected invocation.

This is a **model-layer instruction**, not a bash block. Triage runs
BEFORE Phase 0b (review) and BEFORE Phase 0c (cron registration) — so a
redirect leaves no cron, no marker, no branch, no commits. /do does NOT
write a tracking marker (no new tracking for /do) — there is nothing to
clean up on redirect.

**Test seam (production behavior unaffected).** When
`_ZSKILLS_TEST_HARNESS=1` is set, the model MUST skip the triage Agent
dispatch and instead use the value of `_ZSKILLS_TEST_TRIAGE_VERDICT` as
the verdict. Production invocations (where the harness flag is absent and
the entry-point unset guard at the pre-flight has already cleared the
test vars) always run the full Agent path. Recognized stub values:
`PROCEED`, `REDIRECT:/draft-plan:reason`, `REDIRECT:/run-plan:reason`,
`REDIRECT:/fix-issues:reason`, `REDIRECT:ask-user:reason`.

The model judges `$DESCRIPTION` against this rubric — qualitative,
observable from description text, no LOC counting. /do always works in a
fresh worktree (PR mode) or main (direct/worktree mode), so the "≥3
distinct files in description" rule applies uniformly (no MODE carve-out
needed).

| Signal | Verdict |
|--------|---------|
| Description scopes to one concept | PROCEED |
| ≥ 3 distinct files explicitly named in description | REDIRECT → `/draft-plan` |
| Verbs include any of: `add feature`, `redesign`, `rewrite`, `refactor across` | REDIRECT → `/draft-plan` |
| `and` connects unrelated areas (e.g. "fix nav and update copy") | REDIRECT → `/draft-plan` |
| Vague verbs alone: `improve`, `fix it`, `update`, `clean up` (no concrete object) | REDIRECT → ask user |
| References a GitHub issue number (`#N`, `closes #N`, `fix #N`) | REDIRECT → `/fix-issues` |
| References an existing plan file under `plans/` | REDIRECT → `/run-plan` |

**Worked examples (calibrate the model's PROCEED/REDIRECT calls):**

| Example invocation | Verdict | Why |
|--------------------|---------|-----|
| `/do Fix README typo` | PROCEED | one concept, one likely file |
| `/do Sort the screenshots in session-sequence-snapshots` | PROCEED | one concrete object |
| `/do Update the presentation with Phase 3 results push` | PROCEED | concrete verb + object |
| `/do add dark mode and refactor the worker pool` | REDIRECT → /draft-plan | "and" connects unrelated areas |
| `/do improve` | REDIRECT → ask user | vague verb, no object |
| `/do fix #142` | REDIRECT → /fix-issues | references issue number |

Output one of:

- `PROCEED` — print `Triage: proceeding with /do (<one-line reason>).` Continue to Phase 0b.
- `REDIRECT(target=<skill>, reason=<text>)` — see redirect handling.

**Per-target redirect message templates** (must be exact-text-grep-able).
Each message is **two physical lines** in the printed output (the
linebreak is a real newline, not the literal `\n` characters):

| target | Line 1 | Line 2 |
|--------|--------|--------|
| `/draft-plan` | `Triage: redirecting to /draft-plan. Reason: <reason>` | `This task spans more than one concept; /draft-plan will research and decompose it. Run \`/draft-plan <description>\` instead, or re-invoke with --force to bypass.` |
| `/run-plan` | `Triage: redirecting to /run-plan. Reason: <reason>` | `This task references an existing plan file. Run \`/run-plan <plan-path>\` to execute it, or re-invoke with --force to bypass.` |
| `/fix-issues` | `Triage: redirecting to /fix-issues. Reason: <reason>` | `This task references a GitHub issue. Run \`/fix-issues <issue-number>\` instead, or re-invoke with --force to bypass.` |
| ask-user | `Triage: cannot proceed — description is too vague to act on. Reason: <reason>` | `Re-invoke /do with a concrete description (verb + object + which file/area). --force will not help — vague descriptions cannot be planned.` |

The model implements these as a `printf 'line1\nline2\n' "$REASON"` so
both lines are emitted to stdout and both are independently greppable
from a test fixture.

On REDIRECT and `$FORCE -eq 0`: print the per-target message (both
lines), then `exit 0`. **No marker is written** (no tracking for /do).
No cron. No branch.

On REDIRECT and `$FORCE -eq 1`: print
`Triage: REDIRECT(<target>) overridden by --force; proceeding.`
Continue to Phase 0b.

## Phase 0b — Inline plan + fresh-agent review

After Phase 0a, before Phase 0c (cron registration), the model composes a
short inline plan and dispatches one fresh Agent to review it. This phase
runs BEFORE Phase 0c so a REJECT exits before any `CronCreate` call.

**Skip when `--rounds 0`.** If `$ROUNDS -eq 0`: print to stderr
`WARN: --rounds 0 skips fresh-agent plan review (legacy opt-in).` and
skip review entirely. Continue to Phase 0c.

**Inline plan composition (model-layer).** This is a **model-layer
instruction**, not a bash block. After triage returns PROCEED (or after
`--force` overrides a REDIRECT), the model composes a short inline plan
held in `INLINE_PLAN`. `INLINE_PLAN` is a logical placeholder for text
the model composes in its response. When the reviewer Agent is dispatched,
the model copies the `INLINE_PLAN` text **verbatim** into the Agent prompt
as the `INLINE PLAN ...` section — there is no file read or shell-variable
interpolation; this is a model-to-prompt substitution.

```text
### /do inline plan
**Description:** <DESCRIPTION>
**Mode:** <LANDING_MODE> (or "as inferred from description; will be resolved in Phase 1.5")
**Files (expected):** <comma-separated list, OR "as inferred from description; may be refined during Phase 1 research">
**Approach:** <2-4 sentences>
**Acceptance:** <2-4 bullets>
```

Constraints:

- ≤60 lines total.
- "Files (expected)" is OPTIONAL for /do — the worktree may not exist yet
  for PR mode; the agent will discover files in Phase 1 research. When
  unsure, set to `as inferred from description; may be refined during
  Phase 1 research`.
- The model-authored fields **Approach** and **Acceptance** MUST NOT
  contain the literals for other skills (`/draft-plan`, `/run-plan`,
  `/fix-issues`) — using these in model-authored prose would muddle the
  redirect-message guards.
- The **Description** field is verbatim user input and is exempt — a
  user description that mentions another skill name is the user's
  prerogative.
- Early-stage review judges PLAN STRUCTURE, not file enumeration accuracy.

**Fresh-agent plan review (model-layer).** This is a **model-layer
instruction**, not a bash block.

**Test seam (production behavior unaffected).** When
`_ZSKILLS_TEST_HARNESS=1` is set, the model MUST skip the reviewer Agent
dispatch and instead use the value of `_ZSKILLS_TEST_REVIEW_VERDICT` as
the verdict (one of `APPROVE`, `REVISE: reason`, `REJECT: reason`).
Production invocations always run the full Agent path.

Otherwise dispatch ONE Agent (no model hint — inherit parent) with this
prompt:

```text
You are the REVIEWER agent for /do's pre-execution plan review.

DESCRIPTION the user provided:
[DESCRIPTION]

LANDING_MODE: [LANDING_MODE]

INLINE PLAN the model proposes to execute:
[INLINE_PLAN verbatim]

Your job: judge whether the inline plan, when executed, will produce a
change set that faithfully addresses DESCRIPTION without obvious
omissions or out-of-scope work. Judge PLAN STRUCTURE, not file
enumeration accuracy (file lists may be best-effort at this stage).

OBSERVABLE-SIGNAL RULE (mandatory): count the **Acceptance** bullets in
the inline plan. If >4 Acceptance bullets are present, you MUST return
`VERDICT: REVISE -- too many concepts; consider /draft-plan` regardless
of whether each bullet individually looks reasonable. This is a hard
auto-REVISE — not a judgment call. The Acceptance-bullet ceiling is the
concrete observable that distinguishes "task fits /do" from "task
should /draft-plan." If the model proposes an Acceptance section that
exceeds the ceiling, the inline plan needs to be split, not rubber-stamped.

Return EXACTLY one of these as the FIRST line. APPROVE is a bare line
with no separator; REVISE and REJECT MUST include both an ASCII `--`
separator AND a one-line reason ≤200 chars. No free text after APPROVE
on line 1.

  VERDICT: APPROVE
  VERDICT: REVISE -- <one-line reason ≤ 200 chars>
  VERDICT: REJECT -- <one-line reason ≤ 200 chars>

Then, on subsequent lines, add a short justification (≤ 10 lines) — for
APPROVE this is where you justify, NOT on line 1.
```

**Verdict parser (separator-required for REVISE/REJECT).** Trim trailing
whitespace from the first line, then match against this regex (in
priority order):

```regex
# Bare APPROVE: no trailing text on line 1.
^VERDICT:[[:space:]]+APPROVE[[:space:]]*$

# REVISE/REJECT: separator (--) and reason are REQUIRED.
^VERDICT:[[:space:]]+(REVISE|REJECT)[[:space:]]+--[[:space:]]+(.+)$
```

Reason captured in group 2 of the second regex. Em-dashes (`—`, `–`) in
the iteration prompt template are normalized to ASCII `--` before
insertion (the model performs this normalization when composing the
iteration prompt) so the parser only needs to handle ASCII. If the
first line matches NEITHER regex → treat as a malformed verdict, retry
once with the same prompt; on second malformed → soft-reject (same exit
semantics as REJECT).

**REVISE loop.** At most `$ROUNDS` iterations. On REVISE, the model
rewrites `INLINE_PLAN` using BOTH the verdict reason AND the
justification body, then dispatches a NEW reviewer (single reviewer,
NOT /draft-plan dual-agent). Iteration prompt template:

```text
You are the REVIEWER agent for /do's pre-execution plan review (round [N]).

Prior reviewer (round [N-1]) returned:
  VERDICT: REVISE -- [prior reason]
  Justification:
  [prior justification body verbatim]

The model has REVISED the inline plan in response. New plan below.

DESCRIPTION the user provided:
[DESCRIPTION]
[…rest of original prompt unchanged…]

Judge whether the revision addresses the prior reviewer's reason. Return
the same VERDICT format (APPROVE bare; REVISE/REJECT require -- + reason).
Do not re-flag issues the prior reviewer already accepted; do flag NEW
issues you see.
```

After `$ROUNDS` REVISE cycles → soft-reject (same exit semantics as REJECT).

On APPROVE: print verdict + justification, continue to Phase 0c.

On REJECT and `$FORCE -eq 0`: print verdict, `exit 0`. **No marker is
written** (no tracking for /do). No worktree, no commits, no cron.

On REJECT and `$FORCE -eq 1`: print override message. Continue to Phase 0c.

Orthogonality with `/verify-changes` (Phase 3): pre-review judges PLAN; `/verify-changes` judges DIFF. Both run when both apply: `--rounds > 0` triggers this pre-review (any landing mode); the `push` flag with code changes (`worktree`/`direct` mode only — see Phase 3) triggers /verify-changes after execution. PR mode (Path A) handles its own push internally and does **not** invoke /verify-changes (per `skills/do/SKILL.md` Phase 4 'Not applicable to PR mode' note).

## Phase 0c — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression.

   **For interval-based schedules** (`4h`, `12h`): use the CURRENT minute
   as the offset so the first fire is a full interval from now. Check with
   `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *`

   **For time-of-day schedules**: offset round minutes by a few:
   - `day at 9am` → `3 9 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — `CronList` and check for existing `/do` crons.
   Extract the task description from each cron's prompt by stripping
   `Run /do ` prefix and trailing flags (`every`, `now`, `worktree`, `push`).
   - If an existing cron's extracted description **exactly matches** (case-
     insensitive) the new task's description, replace it (`CronDelete` +
     recreate). This is a re-registration of the same task.
   - Otherwise, keep it — the user has multiple crons for different tasks.
   - During an **unattended cron fire** (the invocation itself came from a
     cron), never ask the user — default to keeping both. During an
     **interactive invocation**, if descriptions are similar but not exact,
     list existing crons and ask: "Replace this one, or keep both?"

3. **Construct `TASK_DESCRIPTION_FOR_CRON`** — strip every/now/--force/--rounds
   tokens from `$ARGUMENTS` but PRESERVE pr/worktree/direct/push tokens (these
   need to round-trip into the cron prompt so each cron fire reproduces the
   user's landing-mode intent).

   Quoted-description carve-out: /do supports a leading quoted description
   (see "Detection" above). When `$ARGUMENTS` begins with `"..."`, peel the
   quoted segment off, strip-chain only the unquoted suffix, then reassemble.
   This prevents `/do "fix --force usage in scripts" --force every 4h` from
   corrupting the user-prose `--force` substring inside the quotes.

   ```bash
   if [[ "$ARGUMENTS" =~ ^([[:space:]]*\"[^\"]*\")[[:space:]]*(.*)$ ]]; then
     QUOTED_HEAD="${BASH_REMATCH[1]}"
     REST="${BASH_REMATCH[2]}"
   else
     QUOTED_HEAD=""
     REST="$ARGUMENTS"
   fi
   STRIPPED_REST=$(echo "$REST" \
     | sed -E 's/(^|[[:space:]])every[[:space:]]+(day|weekday)[[:space:]]+at[[:space:]]+[^[:space:]]+($|[[:space:]])/ /' \
     | sed -E 's/(^|[[:space:]])every[[:space:]]+[^[:space:]]+($|[[:space:]])/ /' \
     | sed -E 's/(^|[[:space:]])now($|[[:space:]])/ /' \
     | sed -E 's/(^|[[:space:]])--force($|[[:space:]])/ /' \
     | sed -E 's/(^|[[:space:]])--rounds[[:space:]]+[0-9]+($|[[:space:]])/ /' \
     | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
   if [ -n "$QUOTED_HEAD" ] && [ -n "$STRIPPED_REST" ]; then
     TASK_DESCRIPTION_FOR_CRON="$QUOTED_HEAD $STRIPPED_REST"
   elif [ -n "$QUOTED_HEAD" ]; then
     TASK_DESCRIPTION_FOR_CRON="$QUOTED_HEAD"
   else
     TASK_DESCRIPTION_FOR_CRON="$STRIPPED_REST"
   fi
   ```

   The time-of-day pattern (`every day at 9am`) MUST come before the
   generic interval pattern (`every 4h`) — generic would otherwise capture
   "day" as the interval value and leave "at 9am" as orphan tokens. The
   `--rounds` strip only matches numeric N (consistent with WI 2a.0's
   greedy-fallthrough rule); a non-numeric `--rounds <prose>` stays in
   `TASK_DESCRIPTION_FOR_CRON` and round-trips into the cron prompt as user
   prose, where it will again no-op-fall-through on each fire.

   **Quoted-description known limit.** A quoted description containing a
   literal `every <token>` substring (e.g., `/do "audit every PR" every 4h`)
   is also protected — only the unquoted suffix is strip-chained. A
   multi-segment quoted form (`/do "fix" --force "every 4h"`) is not
   supported; the regex matches only the leading quote pair.

4. **Construct the cron prompt** incrementally so optional flags only appear
   when set. `FORCE` and `ROUNDS` are pre-parsed in WI 2a.0; `SCHEDULE` is
   parsed in step 1 above. Always include `now` in the cron prompt so each
   cron fire runs immediately AND re-registers itself. Note: this `now` is
   for the CRON's invocation, not the current invocation.

   ```bash
   # Construct cron prompt incrementally so optional flags only appear when set.
   CRON_PROMPT="Run /do ${TASK_DESCRIPTION_FOR_CRON}"  # description with landing/push tokens preserved
   if [ "$FORCE" -eq 1 ]; then
     CRON_PROMPT="$CRON_PROMPT --force"
   fi
   if [ "$ROUNDS" != "1" ]; then
     CRON_PROMPT="$CRON_PROMPT --rounds $ROUNDS"
   fi
   CRON_PROMPT="$CRON_PROMPT every $SCHEDULE now"
   # CronCreate uses $CRON_PROMPT verbatim.
   ```

   **Persistence of `--force` and `--rounds N`:** these flags are preserved verbatim in the cron prompt. A `/do <task> --force every 4h` produces a cron prompt of `Run /do <task> --force every 4h now`, so every cron fire bypasses triage and review. Intentional: setting `--force` on a recurring task means the user wants the bypass on every fire.

5. **Create the cron** — `CronCreate` with `recurring: true`, passing
   `$CRON_PROMPT` verbatim.

6. **Confirm** with wall-clock time.

7. **If `now` is present:** proceed to Phase 1.
   **If `now` is NOT present:** **Exit.** The cron fires later.

If `every` is NOT present, skip this phase (bare invocation runs immediately).

## Phase 1 — Understand & Research

Before touching anything:

1. **Parse the task description** — what is being asked? What files are
   involved? What's the expected outcome?

2. **Identify relevant files and current state:**
   - Search for files related to the task (Glob, Grep)
   - Read existing content that will be modified
   - Check for related skills, conventions, or guidelines (e.g., model
     design rules for example models, newsletter format for entries)

3. **Classify the change type** — this determines verification intensity
   in Phase 3:
   - **Content only** — markdown, images, presentations, documentation.
     No tests needed.
   - **Code** — JavaScript, CSS, HTML, model files. Tests needed.
   - **Mixed** — both content and code. Tests needed for code portion.

4. **Plan the work** — no formal document, just mental clarity on what
   to do and in what order. If the task is bigger than expected (would
   take 1000+ lines of changes, has complex dependencies), suggest
   `/run-plan` instead and ask the user.

## Phase 1.5 — Argument Parsing (always before Phase 1 research)

Before any research or execution, parse flags from `$ARGUMENTS`.

**Step 1: Resolve `LANDING_MODE`.** Precedence: explicit flag (`pr`,
`direct`, `worktree`) → `execution.landing` in
`.claude/zskills-config.json` (`cherry-pick` → `worktree`, `pr` → `pr`,
`direct` → `direct`) → fallback `direct`.

```bash
REMAINING="$ARGUMENTS"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
CONFIG_FILE="$MAIN_ROOT/.claude/zskills-config.json"

ARG_LANDING=""
if [[ "$REMAINING" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then
  ARG_LANDING="pr"
elif [[ "$REMAINING" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  ARG_LANDING="direct"
elif [[ "$REMAINING" =~ (^|[[:space:]])worktree($|[[:space:]]) ]]; then
  ARG_LANDING="worktree"
fi

if [ -n "$ARG_LANDING" ]; then
  LANDING_MODE="$ARG_LANDING"
elif [ -f "$CONFIG_FILE" ] && [[ $(cat "$CONFIG_FILE") =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  case "${BASH_REMATCH[1]}" in
    pr)          LANDING_MODE="pr" ;;
    cherry-pick) LANDING_MODE="worktree" ;;
    direct)      LANDING_MODE="direct" ;;
    *)           LANDING_MODE="direct" ;;  # unknown → safe default
  esac
else
  LANDING_MODE="direct"
fi

# Guard: direct + main_protected is an error (same contract as /run-plan
# and /fix-issues). Prevents silently committing to main when the repo
# requires PR/feature-branch workflow.
if [ "$LANDING_MODE" = "direct" ] && [ -f "$CONFIG_FILE" ] \
   && grep -q '"main_protected"[[:space:]]*:[[:space:]]*true' "$CONFIG_FILE"; then
  echo "ERROR: direct mode is incompatible with main_protected: true. Use pr, worktree, or change config."
  exit 1
fi
```

**Step 2: Derive `TASK_DESCRIPTION`** (strip landing tokens):
```bash
TASK_DESCRIPTION=$(echo "$REMAINING" \
  | sed -E 's/(^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?])/ /' \
  | sed -E 's/(^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])worktree($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--force($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])--rounds[[:space:]]+[0-9]+($|[[:space:]])/ /' \
  | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
if [ -z "$TASK_DESCRIPTION" ]; then
  echo "ERROR: Task description required. Usage: /do <task description> [pr|direct|worktree] [push]"
  exit 1
fi
```

The two new `sed -E` lines strip `--force` and `--rounds N` (numeric N
only) from `TASK_DESCRIPTION` so they don't leak into downstream prompts.
Non-numeric `--rounds <prose>` is left in place — symmetric with the
pre-flight greedy-fallthrough rule (WI 2a.0): a non-numeric trailing
token after `--rounds` is user prose, not a flag, and must NOT raise
exit 2.

**Step 3: Check for `push` flag** (trailing):
```bash
if [[ "$REMAINING" =~ (^|[[:space:]])push($|[[:space:]]) ]]; then
  USE_PUSH=true
fi
```

`pr` takes precedence: if `LANDING_MODE="pr"`, ignore `push` (PR mode handles push internally).

**Step 4: Re-affirm `FORCE` and `ROUNDS`** (already set by the pre-flight
pre-parse; idempotent re-validation in case Phase 1.5 is invoked outside
the normal entry path — defensive). The regex MUST match the pre-flight
exactly: numeric-only `[0-9]+` capture with greedy-fallthrough on
non-numeric (no exit-2 branch — that would contradict the pre-flight's
contract that `/do fix the bug --rounds in production` is a legitimate
description).

```bash
# Re-affirm (already set by pre-flight pre-parse; idempotent).
# Regex is numeric-only — symmetric with WI 2a.0. Non-numeric trailing
# tokens after `--rounds` are user prose (greedy-fallthrough) and DO NOT
# raise exit 2 — that would re-introduce the closed greedy bug.
FORCE=${FORCE:-0}
if [[ "$REMAINING" =~ (^|[[:space:]])--force($|[[:space:]]) ]]; then
  FORCE=1
fi
ROUNDS=${ROUNDS:-1}
if [[ "$REMAINING" =~ (^|[[:space:]])--rounds[[:space:]]+([0-9]+)($|[[:space:]]) ]]; then
  ROUNDS="${BASH_REMATCH[2]}"
fi
```

## Phase 2 — Execute

Select the execution path based on `LANDING_MODE` (resolved in Phase 1.5),
then **read the corresponding mode file in full and follow its
procedure end-to-end**. Do not proceed until you have read the file.

| `LANDING_MODE` | Path | Mode file |
|----------------|------|-----------|
| `pr`           | A    | [modes/pr.md](modes/pr.md) |
| `worktree`     | B    | [modes/worktree.md](modes/worktree.md) |
| `direct`       | C    | [modes/direct.md](modes/direct.md) |

## Phase 3 — Verify

Verification intensity matches the change type (from Phase 1):

### Content-only changes (md, jpg, png, presentations)

- **Spot-check:** formatting, links, file organization, image references
- **Do NOT run tests** — running 4,000+ tests for a markdown edit is
  wasteful, and pre-existing failures would block the task unnecessarily
- **If `push` is present:** dispatch a separate verification agent. Tell
  the agent explicitly: "These are content-only changes (no code). Review
  the diff for correctness and completeness — do NOT run `npm test` or
  `npm run test:all`. Your job is: do these changes make sense? Are the
  right files included? Anything accidentally staged? Formatting correct?"
  Do NOT invoke `/verify-changes` for content-only pushes — it will run
  the full test suite regardless. Instead, dispatch a plain review agent.

### Code changes (js, css, html)

- **Run `$FULL_TEST_CMD`** (resolve via
  `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
  if you don't already have it in your environment) — all suites must pass, not just unit tests.
  **CRITICAL — Bash tool timeout:** invoke with `timeout: 600000` (10
  min); default 120000ms is shorter than the suite's runtime (~3-4
  min). Do NOT recover from a Bash timeout by retrying with
  `run_in_background: true` + `Monitor` / `BashOutput` — wake events
  do not reliably deliver to subagents (you may be one), so the wait
  never returns and the dispatch hangs at "Tests are running. Let me
  wait for the monitor." Past failure: 6+ subagent crashes with that
  phrase across 2026-04-29 and 2026-04-30. Always foreground-Bash with
  explicit long timeout; capture to file; read the file on return.
- **If tests fail: fix them.** Do not check if failures are pre-existing.
  Do not stash, checkout old commits, or create comparison worktrees.
  If you touched code and tests fail, they're yours to fix. (See
  CLAUDE.md: "NEVER modify the working tree to check if a failure is
  pre-existing.")
- **If `push` is present:** dispatch a **separate verification agent**
  running `/verify-changes`. This is the full 7-phase verification:
  diff review, test coverage audit, `npm run test:all`, manual
  verification if UI, fix problems, re-verify until clean. Push only
  happens if this agent reports clean.

### Mixed changes

- Run tests for the code portion
- Spot-check the content portion
- If `push`: full `/verify-changes` via separate agent

## Phase 4 — Push (if `push` flag present, Path C/B only)

Only reached if Phase 3 verification passed. Not applicable to PR mode (Path A — PR mode has its own push in Phase 2 Step A7).

1. **If on main (Path C):**
   ```bash
   git push
   ```

2. **If in worktree (Path B):** cherry-pick to main first, then push:
   - Protect uncommitted work on main (`git stash -u` if needed)
   - Cherry-pick worktree commits to main sequentially
   - If any cherry-pick conflicts: **abort and clean up:**
     ```bash
     git cherry-pick --abort
     ```
     Restore stash if one was created (`git stash pop`). If `/do` has an
     active cron, kill it (`CronList` + `CronDelete` any whose prompt
     starts with `Run /do`). Report the conflict to the user. Do NOT
     force-push or resolve automatically.
   - Restore stash if one was created
   - Push main
   - Report what was pushed (commit hashes, branch)

3. **If verification failed:** do NOT push. Report the verification
   findings and stop.

## Phase 5 — Report

Brief inline output. No persistent report file.

**On main (no worktree, no push):**
```
Done. [1-2 sentence summary of what was done]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
```

**On main with push:**
<!-- allow-hardcoded: npm run test:all reason: report-template example string the agent prints in its completion message; not an executable command -->
```
Done and pushed. [1-2 sentence summary]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
Pushed to: origin/main
Verification: clean (npm run test:all passed, /verify-changes clean)
```

**In worktree (no push):**
```
Done. [1-2 sentence summary]
Worktree: ../do-<slug>/
Branch: do/<slug>
Commits: abc1234, def5678
To land: git cherry-pick abc1234 def5678
To discard: git worktree remove ../do-<slug>/
```

**In worktree with push:**
```
Done and pushed. [1-2 sentence summary]
Cherry-picked to main: abc1234, def5678
Pushed to: origin/main
Verification: clean (/verify-changes clean)
Worktree: ../do-<slug>/ (can be removed)
```

**PR mode (pr flag):**
```
Done. [1-2 sentence summary of what was implemented]
PR: <PR_URL>
Branch: <BRANCH_NAME>
Worktree: <WORKTREE_PATH>
CI: passed | failed | no checks
Status: pr-ready | pr-ci-failing | landed
```

## Error Handling

- **Test failures (code changes):** stop, fix the code, re-test. Never
  weaken tests. Never check if failures are pre-existing.
- **Content issues:** stop, fix formatting/links/references, re-check.
- **Cherry-pick conflict (worktree + push):** stop, report the conflict.
  Do not resolve automatically — conflicts need human judgment.
- **Push failure (auth, remote, etc.):** stop, report the error.
- **Task is bigger than expected:** stop, suggest `/run-plan` instead.
  Ask the user before continuing.
- **PR mode: rebase conflict:** write `.landed` with `status: conflict`,
  report to user, direct them to inspect `$WORKTREE_PATH`.
- **PR mode: CI failure:** write `.landed` with `status: pr-ci-failing`,
  report the failure. Do NOT dispatch fix agents.
- **PR mode: implementation agent fails without committing:** write
  `.landed` with `status: conflict` and exit with an error message.
- **If stuck on anything:** report the state and ask the user for
  guidance. Do not retry the same approach in a loop.

## Key Rules

- **Match verification to change type** — content-only tasks skip tests.
  Code tasks run tests. Push upgrades to full `/verify-changes`.
- **Never weaken tests** — fix the code, not the test.
- **Never modify the working tree to check pre-existing failures** — if
  you touched code and tests fail, fix them. No stash-and-compare, no
  checkout-old-commit, no comparison worktrees.
- **Protect other agents' work** — do not commit unrelated changes that
  happen to be in the working tree. Stage only files related to the task.
- **Worktree naming (worktree flag)** — use `../do-<slug>/` where `<slug>`
  is a short kebab-case description derived from the task (e.g.,
  `do-sort-screenshots`, `do-integrator-examples`). Include a timestamp
  suffix if a worktree with that name already exists. Uses manual
  `git worktree add` — NOT `isolation: "worktree"`.
- **Worktree naming (pr flag)** — use `/tmp/<project>-do-<slug>/` with
  a named branch `<branch_prefix>do-<slug>`. Both BRANCH_NAME and
  WORKTREE_PATH derive from TASK_SLUG (after any collision suffix).
- **No persistent report files** — `/do` outputs results inline. It does
  NOT write SPRINT_REPORT.md, PLAN_REPORT.md, or any other report file.
  The commit is the artifact.
- **Push requires verification** — `push` always dispatches a separate
  verification agent before pushing. No exceptions.
- **PR mode CI is report-only** — `/do pr` polls CI and reports status.
  It does NOT dispatch fix agents. For automated fix cycles, use
  `/run-plan` or `/fix-issues` in PR mode.
- **PR body uses `git log origin/main..HEAD`** — never `git log main..HEAD`
  (local main may be stale after rebase).
- **PR titles and bodies are explicit** — never use `--fill` in `gh pr create`.
- **Slug collision suffix targets TASK_SLUG itself** — not just WORKTREE_PATH.
  Both BRANCH_NAME and WORKTREE_PATH must pick up the suffix.
- **Respect CLAUDE.md** — all standard rules apply (no external deps, no
  bundlers, no weakened tests, etc.)
