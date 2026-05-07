---
name: run-plan
disable-model-invocation: false
argument-hint: "<plan-file> [phase|finish|status] [auto] [pr|direct] [every SCHEDULE] [now] | stop | next"
description: >-
  Execute the next phase of a plan document: parse phases and status, dispatch
  implementation in a worktree, verify with a separate agent, update progress
  tracking, write reports/plan-{slug}.md, and optionally auto-land to main. Can
  self-schedule recurring runs via cron. Use `next` to check schedule, `stop`
  to cancel.
metadata:
  version: "2026.05.07+392b64"
---

# /run-plan \<plan-file> [phase|finish] [auto] [every SCHEDULE] [now] | stop | next — Plan Phase Executor

Orchestrates plan-driven development. Reads a plan document, identifies the
next incomplete phase, dispatches implementation in a worktree, verifies with a
separate agent, updates progress tracking, writes a persistent report, and
optionally auto-lands to main. Can self-schedule for recurring runs to work
through multi-phase plans autonomously.

**Ultrathink throughout.** Use careful, thorough reasoning at every step.

## Arguments

```
/run-plan <plan-file> [phase] [auto] [pr|direct] [every SCHEDULE] [now]
/run-plan stop | next
```

- **plan-file** (required) — path to plan, e.g. `plans/FEATURE_PLAN.md`
- **phase** (optional) — specific phase, e.g. `4a`. If omitted, auto-detect
  next incomplete phase
- **finish** (optional) — run ALL remaining phases sequentially until the
  plan is complete. `finish` is approval to START — do not ask for
  confirmation before the first phase (the user already said "finish").
  Without `auto`: pauses BETWEEN phases to show results and ask "continue
  to next phase?" With `auto`: each phase runs as its own cron-fired
  top-level turn (~5 min between phases via one-shot crons scheduled by
  Phase 5c). The first phase runs immediately; each subsequent phase is
  scheduled after the prior phase lands. Preserves fresh context per
  phase — no late-phase fatigue.
  Each phase still gets full verification, testing, and all safety rails.
  If any phase fails verification or hits a conflict, stops there.
  **`finish` and `every` are mutually exclusive.** `finish auto` schedules
  its own ~5-min one-shot crons internally. `every N` schedules a recurring
  cron at user-set cadence. Combining them would produce two overlapping
  cron schedules. Use one or the other.
- **auto** (optional) — bypass approval gates, auto-land to main via cherry-pick
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Implies `auto` — scheduling only makes sense for autonomous runs
  - Cron prompt omits phase number so each invocation auto-detects the next
    incomplete phase
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior.
- **status** — show plan progress: all phases, their status, what's next,
  and what's blocked. Read-only — no agents dispatched, no approval gate.
- **stop** — cancel any existing `/run-plan` cron and exit. **Takes
  precedence over all other arguments.**
- **next** — check when the next scheduled run will fire. **Takes precedence
  over all other arguments except `stop`.**

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `status` (case-insensitive) — show plan progress and exit
- `finish` (case-insensitive) — run all remaining phases sequentially
- `now` (case-insensitive) — run immediately
- `auto` (case-insensitive) — autonomous mode
- `every` followed by a schedule expression — scheduling mode
- `pr` (case-insensitive) — PR landing mode
- `direct` (case-insensitive) — direct landing mode
- Neither `pr` nor `direct` — read config default (`execution.landing`),
  or `cherry-pick` if no config

**Landing mode resolution:**
1. Explicit argument wins: `pr` or `direct` in $ARGUMENTS
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`

```bash
# Detect landing mode
LANDING_MODE="cherry-pick"  # default
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  # Read config default
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      if [ -n "$CFG_LANDING" ]; then
        LANDING_MODE="$CFG_LANDING"
      fi
    fi
  fi
fi
```

**Validation:**

```bash
# direct + main_protected -> error
if [[ "$LANDING_MODE" == "direct" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      echo "ERROR: direct mode is incompatible with main_protected: true. Use pr mode or change config."
      exit 1
    fi
  fi
fi
```

**Reading branch_prefix from config:**

```bash
# Read branch prefix from config (default: feat/)
BRANCH_PREFIX="feat/"
if [ -f "$PROJECT_ROOT/.claude/zskills-config.json" ]; then
  CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
  # ([^\"]*) allows empty string match -- empty prefix means no prefix
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
fi
```

**Resolving FULL_TEST_CMD from config:**

The orchestrator resolves the test command ONCE here and passes it
verbatim to every impl/verifier/fix-agent dispatch prompt. Three-case
decision tree (same contract as `/verify-changes`):

```bash
FULL_TEST_CMD=""
if [ -f "$PROJECT_ROOT/.claude/zskills-config.json" ]; then
  CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
  if [[ "$CONFIG_CONTENT" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
fi

if [ -n "$FULL_TEST_CMD" ]; then
  # Case 1: config set — use it.
  TEST_MODE="config"
else
  # Check for test infra (same list as preflight hook-placeholder gate):
  # package.json with a "test" script, vitest/jest/pytest configs,
  # Makefile, tests/*.sh, tests/*.py, tests/*.js.
  TEST_INFRA_DETECTED=0
  [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"test"[[:space:]]*:' "$PROJECT_ROOT/package.json" && TEST_INFRA_DETECTED=1
  ls "$PROJECT_ROOT"/vitest.config.* "$PROJECT_ROOT"/jest.config.* "$PROJECT_ROOT"/pytest.ini \
     "$PROJECT_ROOT"/.mocharc.* "$PROJECT_ROOT"/Makefile 2>/dev/null | grep -q . && TEST_INFRA_DETECTED=1
  ls "$PROJECT_ROOT/tests"/*.sh "$PROJECT_ROOT/tests"/*.py "$PROJECT_ROOT/tests"/*.js 2>/dev/null | grep -q . && TEST_INFRA_DETECTED=1

  if [ "$TEST_INFRA_DETECTED" -eq 1 ]; then
    # Case 2: tests exist but no command — misconfigured. Refuse.
    echo "ERROR: /run-plan: test infra detected but testing.full_cmd is empty." >&2
    echo "  Run /update-zskills to configure, or edit .claude/zskills-config.json." >&2
    exit 1
  else
    # Case 3: no test infra, no command — docs-only/greenfield. Skip test gate.
    TEST_MODE="skipped"
    echo "/run-plan: no test infra detected; skipping test gate — will be noted in report."
  fi
fi
```

**Never hardcode `npm run test:all`, `npm start`, or `.test-results.txt`.**
Every subsequent reference uses `$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, and
`$TEST_OUTPUT_FILE`. **Agent dispatch prompts must include the RESOLVED
literal value** of each var (substituted from the helper's output BEFORE
emission), or the explicit "Tests: skipped — no test infra" when
`TEST_MODE=skipped`. Markdown blockquotes (e.g., the worktree-test recipe
at lines 898-930) do NOT undergo parameter expansion at emission time —
YOU, the orchestrator-model, must perform the substitution before typing
the blockquote into the subagent's prompt.

To resolve all three vars in one step (sibling resolution to the
`$FULL_TEST_CMD` decision tree above), source the helper:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
# Informational fallbacks for the recipe (non-critical-path):
[ -z "$DEV_SERVER_CMD" ] && DEV_SERVER_CMD=npm
[ -z "$TEST_OUTPUT_FILE" ] && TEST_OUTPUT_FILE=.test-results.txt
```

Note: if `dev_server.cmd` is unset, the recipe instructs `npm` as a
sensible default; configure `dev_server.cmd` for non-npm projects.
The `testing.output_file` filename suffix is informational (not
load-bearing for project semantics) — fallback to `.test-results.txt`
is safe.

**Strip `pr`/`direct` from arguments** before passing to downstream processing
(same pattern as stripping `auto`, `finish`, etc.).

Examples:
- `/run-plan plans/FEATURE_PLAN.md` — interactive, next phase
- `/run-plan plans/FEATURE_PLAN.md 4b` — interactive, specific phase
- `/run-plan plans/FEATURE_PLAN.md finish` — interactive, all remaining phases (pauses between each)
- `/run-plan plans/FEATURE_PLAN.md finish auto` — autonomous, all remaining phases (chunked, one phase per cron turn)
- `/run-plan plans/FEATURE_PLAN.md auto every 4h` — schedule every 4h
- `/run-plan plans/FEATURE_PLAN.md auto every 4h now` — schedule + run now
- `/run-plan plans/FEATURE_PLAN.md finish auto pr` — autonomous, all phases, PR landing
- `/run-plan plans/FEATURE_PLAN.md direct` — direct mode, work on main
- `/run-plan plans/FEATURE_PLAN.md status` — show plan progress
- `/run-plan now` — trigger the active cron early
- `/run-plan stop` — cancel scheduled runs
- `/run-plan next` — check when the next phase will run

## Status (if `status` is present)

If `$ARGUMENTS` contains `status` (case-insensitive):

1. Compute the authoritative plan-file path — same logic as Phase 1's
   "Read authority" section, duplicated here because `status` exits
   before Phase 1 preflight:
   ```bash
   PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   PROJECT_NAME=$(basename "$MAIN_ROOT")
   PR_WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
   if [ "$LANDING_MODE" = "pr" ] && [ -d "$PR_WORKTREE_PATH" ]; then
     PLAN_FILE_FOR_READ="$PR_WORKTREE_PATH/$PLAN_FILE"
   else
     PLAN_FILE_FOR_READ="$MAIN_ROOT/$PLAN_FILE"
   fi
   ```
   Read the plan from `$PLAN_FILE_FOR_READ` so PR-mode in-flight tracker
   updates (committed on the feature branch) surface correctly instead
   of main's stale copy.
2. Also read any companion progress document if referenced (same rule).
3. Parse all phases and their status (same parsing logic as Phase 1
   steps 2-3: "Extract phases and status" and "Determine target phase."
   Do NOT run preflight checks — `status` is read-only)
4. Present a progress table:

   ```
   Plan: plans/FEATURE_PLAN.md

   | Phase | Status |
   |-------|--------|
   | 4a — Electrical | Done (abc1234) |
   | 4b — Mechanical | Done (def5678) |
   | 4c — Smooth Nonlinear | Next ← |
   | 4d — Solver Fixes | Blocked (needs 4c) |
   | 4e — UI Polish | Blocked (needs 4d) |

   Next phase: 4c — Smooth Nonlinear Components
   Dependencies: 4a ✓, 4b ✓
   ```

5. If a cron is active, also show the schedule:
   > Scheduled: every 4h (~8:15 PM ET next, cron XXXX)

6. **Exit.** Read-only — no agents dispatched, no work done.

## Now (standalone — no plan-file provided)

If `$ARGUMENTS` is just `now` (no plan-file, no phase, no every):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /run-plan`
3. If found: extract the cron's prompt to get the plan-file, auto, and
   schedule. **Run the phase immediately** — proceed to Phase 1. Do NOT
   ask for confirmation — `now` IS the confirmation. The cron stays active.
4. If none found: report `No active /run-plan cron to trigger. Use
   /run-plan <plan-file> to run manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /run-plan`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next run-plan phase in ~2h 15m (~8:30 PM ET, cron XXXX).
     > Prompt: Run /run-plan plans/FEATURE_PLAN.md auto every 4h
   - If none found: `No active /run-plan cron in this session.`
4. **Exit.** Do not proceed to any phase.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /run-plan` using `CronDelete`
3. Clean up any per-phase defer counters and recovery sentinels for this
   plan (#110). MAIN_ROOT and TRACKING_ID are not yet in scope here, so
   compute them inline:
   ```bash
   TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
   ```
4. Report what was cancelled:
   - If one cron found: `Run-plan cron stopped (was job ID XXXX, every INTERVAL).`
   - If multiple found: `Stopped N run-plan crons (IDs: XXXX, YYYY).`
   - If none found: `No active /run-plan cron found.`
5. **Exit.** Do not proceed to any phase. The `stop` command does nothing else.

## Phase 0 — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression. The LLM interprets
   natural scheduling expressions.

   **For interval-based schedules** (`4h`, `2h`, `30m`): use the CURRENT
   minute as the offset so the first fire is a full interval from now, not
   aligned to midnight. Check the current minute with `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *` (fires at :09 past every 4th hour)
   - `2h` at minute 15 → `15 */2 * * *`
   - `30m` → `*/30 * * * *` (no offset needed for sub-hour)
   - `1h` at minute 9 → `9 * * * *`

   **For time-of-day schedules** (`day at 9am`, `weekday at 2pm`): offset
   round minutes by a few to avoid API busy marks:
   - `day at 9am` → `3 9 * * *`
   - `day at 14:00` → `3 14 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — use `CronList` + `CronDelete` to remove any whose
   prompt starts with `Run /run-plan`.

3. **Construct the cron prompt.** Strip the phase number (so each invocation
   auto-detects the next incomplete phase). Always include `now` in the cron
   prompt so each cron fire runs immediately AND re-registers itself. Note:
   this `now` is for the CRON's invocation, not the current invocation:
   ```
   Run /run-plan <plan-file> auto every <schedule> now
   ```
   Note: the phase number is intentionally omitted so the cron auto-advances.

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the constructed command from step 3

5. **Confirm** with wall-clock time. **Always show times in America/New_York
   (ET)** — use `TZ=America/New_York date` for conversion, not the system
   timezone (which may be UTC):

   If `now` is present:
   > Run-plan scheduled every 4h. Running now.
   > Next phase run after this one: ~8:15 PM ET (cron ID XXXX).

   If `now` is NOT present:
   > Run-plan scheduled every 4h.
   > First run: ~4:15 PM ET (cron ID XXXX).
   > Use `/run-plan next` to check, `/run-plan stop` to cancel.

6. **If `now` is present:** proceed to Phase 1 (run immediately).
   **If `now` is NOT present:** **Exit.** The cron fires later.

**End-of-phase scheduling note:** when a phase finishes and a cron is
active, always include the estimated next run time with timezone in the
completion message. Example:
> Phase complete. Next phase run in ~3h 45m (~11:30 PM ET, cron XXXX).

If `every` is NOT present, skip this phase and proceed to Phase 1
(bare invocation always runs immediately).

## Phase 1 — Parse Plan & Extract Verbatim Phase Text

The key differentiator. Plans have varied formats, so the agent uses LLM
comprehension rather than rigid parsing.

### Read authority (PLAN_FILE_FOR_READ) — compute before ANY plan read

Before any read of the plan file (frontmatter, tracker, phase text), compute
the authoritative source for this invocation.

**Why this matters.** In PR mode, per-phase tracker updates (`🟡 In Progress`
→ `✅ Done`, `status: complete`) commit on the **feature branch**, per the
PR-mode bookkeeping rule. Main's copy of the plan file is stale across
cron-fired `finish auto pr` re-entries until the squash merge lands at plan
completion. A naive `cat plans/<plan>.md` from the orchestrator's CWD (main)
would silently show `⬚/⬚` on turn 2 even when Phase 1 is already done on
the feature branch — causing the re-entry check to re-execute already-done
phases. Cherry-pick and direct modes commit bookkeeping on main directly, so
main is authoritative there.

```bash
# Compute BEFORE Step 0. LANDING_MODE is already resolved from args/config
# in the argument-detection section at the top of this skill.
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PROJECT_NAME=$(basename "$MAIN_ROOT")
PR_WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"

if [ "$LANDING_MODE" = "pr" ] && [ -d "$PR_WORKTREE_PATH" ]; then
  PLAN_FILE_FOR_READ="$PR_WORKTREE_PATH/$PLAN_FILE"
  echo "PR-mode re-entry: reading plan from feature-branch worktree at $PR_WORKTREE_PATH"
else
  PLAN_FILE_FOR_READ="$MAIN_ROOT/$PLAN_FILE"
fi
```

**Every subsequent plan read MUST use `$PLAN_FILE_FOR_READ`**, including
Step 0's re-entry check, all of Parse Plan's steps, and the Status command
(which duplicates this computation for its own read-only early-exit path).
The plain `$PLAN_FILE` (relative to CWD) would silently point at main's
stale copy in PR-mode chunked re-entries.

**Writes are unaffected.** Phase 4 tracker updates and Phase 5b frontmatter
updates continue to follow the PR-mode bookkeeping rule (commit on feature
branch in PR mode; commit on main in cherry-pick/direct mode). Only the
read path needed the explicit branch.

### Preflight checks

Before parsing, check for stale state from a previous failed run:

0. **Idempotent re-entry check (chunked finish auto only).** If running
   with `finish auto`, this turn may have been triggered by a cron from
   a previous turn. Re-emit the pipeline ID first (cron-fired turns are
   fresh sessions):
   ```bash
   TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')
   echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"
   ```

   **Sentinel-recovery prelude (#110).** Before evaluating the four cases
   below, check for a `cron-recovery-needed.<phase>` marker left by a prior
   turn whose CronCreate failed after a successful CronDelete (high-severity
   race documented in WI 1.3 step 4d). The marker means the recurring `*/1`
   cron may not exist; this turn must try to re-establish it before doing
   anything else. The counter is held — this is recovery, not normal flow.

   ```bash
   # MAIN_ROOT is already in scope from the "Read authority" block earlier
   # in this section (line ~393); reuse it here.
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   if compgen -G "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed.*" >/dev/null 2>&1; then
     # CronList → check if a "Run /run-plan <plan-file> finish auto" cron
     # already exists (a stale fire from before the failed Delete may have
     # raced ahead of us).
     # If exists AND cadence ∈ {*/1, */10, */30, */60} (sane backoff cadence
     #   set, A1 fix): rm cron-recovery-needed.* (already recovered at a
     #   sane cadence; trust it).
     # If exists BUT cadence ∉ {*/1, */10, */30, */60} (A1 fix: third-party
     #   cron at e.g. */15, or scheduler corruption returning bad cadence):
     #   emit WARN cron-recovery-bad-cadence with the observed cadence
     #   string, force CronDelete on ALL matching crons, then fall through
     #   to the "missing" branch below to CronCreate at */1.
     # If missing: CronCreate cron="*/1 * * * *" recurring=true
     #             prompt="Run /run-plan <plan-file> finish auto"
     #             then verify via CronList again AND verify the new cron's
     #             cadence is exactly "*/1 * * * *" (not just "exists").
     #             On success: rm cron-recovery-needed.*. On failure: leave
     #             marker, emit WARN cron-recovery-failed and continue to
     #             case dispatch (Case 3's own inline retry may succeed, or
     #             Case 4 will happy-path past the missing cron).
   fi
   ```

   The cadence-sanity check (A1 fix) protects against three failure modes:
   (i) a third-party tool created a recurring cron with the same prompt at
   a different cadence (e.g., `*/15`); (ii) Case 3's 3-retry exhaustion left
   a partial-success cron at the wrong target cadence; (iii) the previous
   turn's CronCreate raced with another top-level invocation. Without this
   check, the "exists, rm marker" branch would silently accept a wrong
   cadence and the pipeline would run at the wrong fire rate indefinitely.

   Then read the plan frontmatter (`status` field) and the plan tracker
   (phase statuses) from `$PLAN_FILE_FOR_READ` (computed in the "Read
   authority" section above — NOT from main's copy of the plan). Four cases:

   1. **Frontmatter `status: complete`**: plan truly done. **Terminal
      cron cleanup (Design 2a):** call `CronList` and `CronDelete` on
      any job whose prompt matches `Run /run-plan <plan-file> finish auto`
      for THIS plan file. In Design 2a chunking, the recurring `*/1`
      cron will otherwise keep firing forever — Case 1 is the only
      routine termination path. Also rm any leftover recovery sentinel
      and per-phase defer counters so the next pipeline starts clean
      (R6 fix, #110):
      ```bash
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
      rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
      rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
      ```
      Then exit with "Plan complete (already).
      Cron <id> deleted." No more work, no more fires.
   2. **All phases Done + frontmatter NOT complete**: Phase 5b needs to
      run (it owns the final-verify gate logic via its new first
      sub-step). Skip Phase 1 sub-steps 1–9 and Phases 2–5; **route
      directly to Phase 5b**. Phase 5b's gate handles the
      verify-pending vs verify-fulfilled vs no-marker cases — single
      source of truth, no duplicated logic in Step 0.
   3. **Next-target phase already In Progress** (per tracker): apply the
      adaptive backoff decision rule (#110). The pipeline cron stays at
      its current cadence on most fires and steps down to a slower
      cadence only at boundary fires `C+1 ∈ {1, 10, 16, 26}`. The
      counter `C` is per-phase scoped:

      1. Read `C` from
         `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers.<phase>`
         (default `0` if missing).
      2. Read current cadence `R` via `CronList` substring match on
         `Run /run-plan <plan-file> finish auto`. If multi-match, pick
         the first for cadence read (the delete-all step in 4 collapses
         all). If no match: emit `WARN no-cron-match`, do NOT increment
         counter, output the defer message, exit.
      3. Compute target cadence `T` from `C+1`:
         `<10` → `*/1`, `10..15` → `*/10`, `16..25` → `*/30`,
         `≥26` → `*/60`.
      4. If `T != R`:
         a. CronList → enumerate ALL prompts containing
            `Run /run-plan <plan-file> finish auto`.
         b. CronDelete each ID.
         c. CronCreate ONE cron with `cron: T`, `recurring: true`,
            `prompt: "Run /run-plan <plan-file> finish auto"`.
         d. Verify: CronList again; if no match found OR cadence != `T`,
            `sleep 2` between retry attempts (N1 fix: inter-attempt
            spacing protects against rate-limit-class CronCreate
            failures, which would otherwise burn all 3 retries inside
            the same rate-limit window), then retry steps c–d up to 2
            more times (3 total CronCreate attempts; total worst-case
            wall-time on the failing path ≈ 4-6s of sleep + 6 LLM tool
            calls). If all 3 attempts fail: write
            `cron-recovery-needed.<phase>` marker, emit
            `WARN cron-replace-failed (3 retries exhausted)` to stdout
            AND output a prominent user-visible WARN to the turn's final
            message:

            > ⚠ /run-plan finish auto: failed to update cron after 3 attempts.
            > Pipeline is stalled until you re-invoke /run-plan <plan>
            > finish auto.
            >
            > If the next invocation also fails: run `/run-plan stop` to
            > clear all crons, then file an issue at
            > github.com/zeveck/zskills-dev/issues/new with the contents of
            > .zskills/tracking/<pipeline-id>/cron-recovery-needed.<phase>
            > and your `CronList` output.

            (N2 fix: explicit escalation path — `/run-plan stop` + manual
            `gh issue` filing — so users have a complete action ladder
            rather than a re-invoke-or-give-up choice.)

            Do NOT increment counter. Exit.
      5. If `T == R`: no cron action.
      6. Write `C+1` to the counter file
         `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers.<phase>`.
         Output the defer message ONLY at `C+1 ∈ {1, 10, 16, 26}`
         (silent on intermediate fires so users see meaningful step-down
         events but not minute-by-minute noise):

         > Phase X already in progress, deferring. Backoff cadence now T.
   4. **Otherwise**: proceed with normal preflight (steps 1–9) then
      Phase 2. Before proceeding, clear all per-phase defer counters and
      any stale recovery sentinel from a prior phase (#110):
      ```bash
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
      rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
      rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
      ```
      (Harmless on first phase — rm of missing files is a no-op.)

   Stale crons are harmless — duplicate fires exit cleanly via this
   check. Re-entry routes to Phase 5b which owns verify-pending state
   and self-rescheduling.

1. **In-progress git operation?**
   ```bash
   ls .git/CHERRY_PICK_HEAD .git/MERGE_HEAD .git/REBASE_HEAD 2>/dev/null
   git status --porcelain | grep '^UU\|^AA\|^DD'
   ```
   If either command produces output, **STOP.** Invoke the Failure Protocol.

2. **Stash stack?**
   ```bash
   git stash list
   ```
   If there is a stash with message containing "pre-cherry-pick", a previous
   run's stash was never restored. **STOP.** Invoke the Failure Protocol —
   the user needs to `git stash pop` or `git stash drop` before a new phase
   can start safely.

3. **Leftover plan worktrees?**
   ```bash
   git worktree list
   ```
   If worktrees from a previous run exist (paths containing `plan-`), warn
   the user. Do not remove them — note their presence and continue.

4. **Unconfigured hook placeholders?**
   ```bash
   grep -qE '^(UNIT_TEST_CMD|FULL_TEST_CMD)=.*\{\{' .claude/hooks/block-unsafe-project.sh 2>/dev/null
   ```
   This gate is an **early-exit mirror** of the hook's own commit-block:
   when `UNIT_TEST_CMD` or `FULL_TEST_CMD` has unreplaced placeholders AND
   test infrastructure exists, the hook will block the eventual `git
   commit` with *"Test infrastructure detected but FULL_TEST_CMD not
   configured"* — so catching it at preflight just prevents wasted work.
   Its job is to notice when a project *has* test infrastructure but the
   hook doesn't yet know about it.

   **Scope matters.** A bare `grep '{{' <file>` false-positives on
   intentional placeholders that the hook itself leaves in (e.g.
   `UI_FILE_PATTERNS="{{UI_FILE_PATTERNS}}"` as a runtime "UI not
   applicable here" sentinel, especially common in the zskills source
   tree where the hook is a template). The anchored grep mirrors the
   hook's actual runtime check (`block-unsafe-project.sh:179`) which
   only fires on `UNIT_TEST_CMD` / `FULL_TEST_CMD` containing `{{`.

   Three cases, report each explicitly so the reasoning is legible:

   - **Placeholders found AND test infra exists** — where test infra means
     any of: `package.json` with a `"test"` script, `vitest.config.*`,
     `jest.config.*`, `pytest.ini`, `.mocharc.*`, or `Makefile` (this list
     must match `block-unsafe-project.sh:134-147` exactly, otherwise
     preflight under-reports and the hook still blocks at commit time):
     **STOP.** Hook placeholders have not been configured — run
     `/update-zskills` first, or (if this plan's purpose is to configure
     them) have the plan land those changes in an early phase before real
     enforcement matters. Report: *"hook-placeholder gate tripped:
     placeholders present AND test infra detected — stopping."*
   - **Placeholders found, no test infra**: gate silent, proceed. This is
     either a fresh/bootstrap project or one with no tests by design. If
     the plan establishes tests, **it should also fill the hook
     placeholders** (`UNIT_TEST_CMD`, `FULL_TEST_CMD`, and
     `UI_FILE_PATTERNS` in `.claude/hooks/block-unsafe-project.sh`) in the
     same phase, so subsequent runs have real enforcement. Report: *"gate
     silent: placeholders present but no test infra yet — bootstrap or
     tests-by-design; if this plan adds tests, also fill the hook
     placeholders."*
   - **No placeholders**: hook is configured, nothing to do. Report:
     *"hook configured; gate n/a."*

5. **Clean up landed worktrees from previous phases**
   ```bash
   for wt_line in $(git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //'); do
     if [ -f "$wt_line/.landed" ] && grep -q 'status: landed' "$wt_line/.landed"; then
       echo "Cleaning up landed worktree: $wt_line"
       bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/land-phase.sh" "$wt_line"
     fi
   done
   ```
   This catches stragglers from crashed agents, container restarts, or any
   remaining edge cases. Defense in depth — `.claude/skills/commit/scripts/land-phase.sh` is the
   primary fix (called after each phase landing), the preflight is the safety net.

### Plan-cited preflights — open-PR file-path conflict gate

When a plan touches a path prefix (e.g. `skills/update-zskills/`) across
multiple phases AND runs in PR mode, every phase's preflight needs to
self-filter the pipeline's OWN PR. Inlining `gh pr list --state open --limit
100 --json number,title,files | grep -F '<prefix>'` in each phase trips the
gate from Phase 2 onward, because the pipeline's own feature branch becomes
the only matching PR (issue #177).

Plans MUST cite the helper instead of inlining the gh+grep pattern:

```bash
# In a plan phase that needs an open-PR conflict gate. The orchestrator
# already tracks $RUN_PLAN_PR_NUMBER (the pipeline's own PR) — pass it via
# --exclude-pr so the gate self-filters.
if ! bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/pr-preflight.sh" \
     --path-prefix "skills/update-zskills/" \
     --exclude-pr "${RUN_PLAN_PR_NUMBER:-}"; then
  echo "FAIL: open PR(s) touch the path; coordinate before continuing." >&2
  exit 1
fi
```

The helper:
- Takes `--path-prefix <prefix>` (required) and `--exclude-pr <num>` (optional).
- Emits matching PR numbers on stdout, one per line; empty when clean.
- Exit 0 when clean, 1 when at least one matching PR remains, 2 on arg or
  gh error.
- `--exclude-pr` may be empty — the script then performs no exclusion, so
  it is safe to call BEFORE the orchestrator knows the pipeline's PR
  number (e.g. Phase 1 of a plan that has not yet been pushed).

Source: `skills/run-plan/scripts/pr-preflight.sh`. Pure bash; no `jq`.

### Parse plan

1. **Read the plan file** in full from `$PLAN_FILE_FOR_READ` (see "Read
   authority" section above — in PR mode with an existing feature-branch
   worktree, this resolves to the worktree's copy; otherwise main's copy).
   Also read any companion progress document if referenced (e.g.,
   `FEATURE_PROGRESS_AND_NEXT_STEPS.md`) — same path rule applies.

2. **Extract phases and status** — handle four formats:
   - **Progress tracker table** (FEATURE_PLAN style): rows with `✅ Done`,
     `⬚` (not started), `🟡` (in progress), etc.
   - **Numbered phase sections** (`## Phase 4a — Title`): look for completion
     markers in the section body or companion doc
   - **Checklist** (`- [x]` / `- [ ]`): checked = done, unchecked = not done
   - **Narrative**: infer status from codebase evidence (files exist, tests
     pass, etc.)

3. **Determine target phase:**
   - If phase arg given: use it. If already complete, warn (or skip in auto)
   - If no phase arg: first incomplete phase
   - If ALL phases complete:
     - If frontmatter `status: complete`: report "Plan complete" → stop.
       If `every`, delete the cron via `CronList` + `CronDelete`.
     - If frontmatter NOT complete: route to Phase 5b directly (Phase 5b's
       gate handles final-verify deferral; if final-verify is satisfied or
       not required, Phase 5b completes the plan).
   - If multiple phases share the same number (e.g., 4a, 4b, 4c), treat
     each sub-phase as a separate phase

4. **Check dependencies** — if a prerequisite phase isn't Done, **STOP.**
   Report which dependency is missing. If `every`, the cron retries later.

5. **Check for conflicts** — if the target phase is "In Progress" (🟡 or
   equivalent), another agent may be working on it. **STOP.** Do not compete.

6. **Check for staleness.** Two independent checks:

   **a. Textual staleness.** if the plan's Dependencies section
   contains language like "drafted before," "may need refresh," or "APIs
   and data structures referenced here are based on [another plan's]
   design, not actual code," the plan may be stale:
   - Without `auto`: tell the user "this plan was drafted before its
     dependency was implemented. Want me to refresh it with `/draft-plan`?"
   - With `auto`: dispatch `/draft-plan` on the plan file to update it.
     `/draft-plan` handles existing files as modernizations. After the
     refresh, re-read the plan and continue.
   - Skip this check if the plan file was modified more recently than
     the dependency's completion (it may already be up to date).

   **b. Arithmetic staleness (pre-dispatch).** For the target
   phase's `### Acceptance Criteria` section, extract numeric
   targets and verify against current source.

   Procedure:
   1. Read the target phase's `### Acceptance Criteria` bullets.
   2. For each bullet, attempt to match a numeric claim via the
      token-compatible grammar (Phase 1 `<stated>` forms: N-M,
      ≤N, ≥N, ~N, exactly N). Unmatched bullets skip.
   3. For each matched claim, locate the corresponding extraction
      rule (if any) in the target phase's `### Design &
      Constraints` section. Supported rules:
      - Literal arithmetic expression: "N - M + K" → evaluate via
        `.claude/skills/run-plan/scripts/plan-drift-correct.sh --eval "N - M + K"`
        (the script implements parse-only integer arithmetic; no
        shell eval, no injection surface).
      - "extract lines N..M" or "lines N-M" → value is M - N + 1.
      - "SKILL.md X lines down from Y" → value is Y - X or X (case-
        by-case; script uses a small fixed set of patterns).
      - No derivable rule → skip bullet, emit info line:
        "pre-dispatch arithmetic check: <bullet> skipped (no
        derivable rule)".
   4. Compute drift between stated target and derived value.
      Use the same `--drift` command as Phase 3.5.
   5. Collect findings per bullet.

   Decision:
   - **Without `auto`:** present findings:
     ```
     Pre-dispatch arithmetic drift:
     Phase <N>: <bullet-text>
       plan says: <stated>
       arithmetic says: <derived>
       drift: <pct>%
     ```
     Ask user: "(1) proceed (Phase 3.5 will post-correct small
     drift), (2) pause for `/refine-plan`, (3) override (suppress
     this check for this phase)?"
   - **With `auto`:** if any bullet has drift >20%, dispatch
     `/refine-plan <plan-file>` (plan-level issue, not per-band);
     after refresh, re-read and continue. If all drifts are
     ≤20%, log findings to the phase report and proceed — Phase
     3.5 will auto-correct post-hoc within the ≤20% band.

7. **Save the VERBATIM phase text** — copy the entire section from the plan
   file exactly as written. Every sentence, every bullet, every formula, every
   constraint. This text will be passed to agents in Phase 2 and Phase 3.

   **Do NOT summarize, paraphrase, or reinterpret.** The plan is the spec.

   Lesson from `/fix-issues` #387: summarized descriptions caused agents to
   implement the wrong thing. "Reset button" was interpreted as "clear canvas"
   instead of "reset mappings to defaults" because only the title was read.
   The same will happen with plan phases if the orchestrator summarizes
   "implement translational mechanical domain" without the formulas, state
   equations, and design constraints.

8. **Create tracking fulfillment marker.** Determine the tracking ID: use
   the ID passed by the parent skill if this is a delegated invocation, or
   derive from the plan file slug if standalone (e.g., `FEATURE_PLAN.md` →
   `feature-plan`). Then create the fulfillment file in the MAIN repo:
   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
   printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: started\ndate: %s\n' \
     "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID"

   # Lock down verification requirement IMMEDIATELY (was Phase 2,
   # now skill entry — ensures hook blocks landing even if Phase
   # 2/3 are skipped via error path). Delegation: verify-changes is
   # a child of run-plan in this pipeline, so its `requires.*` marker
   # lives in run-plan's OWN subdir (parent reconciles fulfillment).
   printf 'skill: verify-changes\nparent: run-plan\nid: %s\ndate: %s\n' \
     "$TRACKING_ID" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.verify-changes.$TRACKING_ID"
   ```

9. **Classify UI impact from the plan text.** Scan the phase description
   for UI indicators: mentions of editor, toolbar, canvas, panel, dialog,
   CSS, button, menu, viewport, renderer, dark mode, layout, or any
   reference to UI/editor/styles directories in the project.
   Flag the phase as **UI-touching** if any are found.

   In `finish` mode, classify ALL phases upfront and report:
   > Running 5 phases. Phases 3 and 5 touch UI — landing will wait for
   > your sign-off at the end.

   This tells the user immediately whether the run will be fully automatic
   or will need their review before landing. No surprises at Phase 6.

9. **Present the phase plan:**
   - Without `auto`: display the phase summary (name, status, dependencies,
     work items, UI classification) and **wait for user approval**
   - With `auto`: proceed immediately

### `finish` mode: overall verification after all phases

In `finish` mode, after ALL phases complete their per-phase implement →
verify loops, run a **final overall verification** before writing the
report and landing:

1. **Dispatch an overall verification agent.** In worktree mode, run
   `/verify-changes worktree` on the full worktree diff. In delegate mode
   (or mixed), run `/verify-changes` on main against the commits from all
   phases combined. This catches cross-phase integration issues: regressions
   from later phases breaking earlier work, conflicting imports, duplicated code.

2. **If ANY phase was classified as UI-touching** (step 7), dispatch a
   **dedicated manual testing agent** that exercises ALL UI changes together
   via playwright-cli. This agent:
   - Tests the combined UI state (not each change in isolation)
   - Takes comprehensive screenshots showing everything working together
   - Prepares the sign-off report so the user can review efficiently
   - Uses `/manual-testing` recipes for selectors and setup

   The goal: instead of "3 items need sign-off, go check yourself," the
   user gets "3 items need sign-off, here are screenshots of all of them
   working together."

3. Proceed to Phase 5 (write report) with the combined verification results.

## Phase 2 — Implement

### Execution mode detection

Check the phase text for an execution mode directive:

- **`### Execution: delegate <skill> [args]`** — delegate mode. The phase
  runs a skill (e.g., `/add-block`, `/run-plan`) that manages its own
  isolation. The orchestrating agent runs on **main**, not in a worktree.
  See "Delegate mode" below.
- **`### Execution: worktree`** or **no directive** — default worktree mode.
  See "Worktree mode" below.
- **`### Execution: direct`** — direct mode. No worktree — agent works
  directly on main. Phase 6 is a no-op (work is already on main). Only
  valid when `LANDING_MODE` is `direct` (validated in argument detection).
  See "Direct mode" below.

### Delegate mode

The orchestrating agent runs on main and calls the specified skill. The
skill manages its own worktree, verification, and landing.

1. **Dispatch agent on main** (no `isolation: "worktree"`). Give the agent:
   - The verbatim phase text (same rule as worktree mode)
   - Instruction to run the specified skill with the given arguments
   - Instruction to wait for the skill to finish and report the result

2. **Agent timeout: 2 hours.** Same as worktree mode.

3. **After the delegate skill finishes**, /run-plan proceeds to Phase 3
   (verification) which runs on main — checking that the delegated work
   actually landed correctly.

4. **In `finish` mode:** each delegate phase runs independently (no shared
   worktree — the delegate skill creates and destroys its own).

Use cases:
- `### Execution: delegate /add-block DiscreteFilter` — block expansion
- `### Execution: delegate /run-plan plans/SUB_PLAN.md finish auto` — meta-plans
- `### Execution: delegate /draft-plan plans/FOO.md <description>` — plan generation

### Plan-text drift signals

Include this VERBATIM in the dispatch prompt (delegate mode) so the
delegated skill's implementing agent surfaces stale numeric acceptance
criteria during its work:

> If during your work you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

Tokens are parsed by `.claude/skills/run-plan/scripts/plan-drift-correct.sh --parse <report-file>`
in Phase 3.5. Format is single-line, space-delimited; `<field>` MUST NOT
contain `:` or `=`.

### Direct mode

When `LANDING_MODE` is `direct`:
- Do NOT create a worktree
- Agent works directly on main (current working directory)
- `### Execution: direct` in phase text is the recognized directive
- Phase 6: no-op (work is already on main, nothing to land)
- `.landed` marker: not written (no worktree to mark)

**Validation (already checked in argument detection):** `direct` + `main_protected: true` -> error before dispatch.

### Worktree mode (default)

One worktree for the entire phase (not per-item like `/fix-issues`).
**In `finish` mode, reuse the SAME worktree across all phases** — create
it once before the first phase, pass the same path to every phase's agent:

**Agent timeout: 2 hours.** Note the dispatch time. If the implementation
agent hasn't returned after 2 hours, declare it **failed**:
- Mark the phase as "Timed out" in `reports/plan-{slug}.md`
- The phase stays incomplete for the next run
- The worktree is a cleanup artifact — do NOT auto-land late results
- If the agent eventually returns, ignore it. Timed out = failed, period.
- If the plan was drafted with `/draft-plan`, the phase may be too large —
  consider splitting it (each phase should be ~3-5 components, ~500 lines).

1. **Create worktree via `.claude/skills/create-worktree/scripts/create-worktree.sh`** (do NOT use `isolation: "worktree"`):
   ```bash
   PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   WT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
     --prefix cp \
     --purpose "run-plan cherry-pick; plan=${PLAN_SLUG}; phase=${PHASE}" \
     --pipeline-id "run-plan.${TRACKING_ID}" \
     "${PLAN_SLUG}-phase-${PHASE}")
   RC=$?
   if [ "$RC" -ne 0 ]; then
     echo "create-worktree failed (rc=$RC) for cherry-pick mode" >&2
     exit "$RC"
   fi
   WORKTREE_PATH="$WT"
   # Derived by create-worktree.sh: path ${WORKTREE_ROOT}/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE},
   # branch cp-${PLAN_SLUG}-phase-${PHASE} (unified across modes — used by post-run-invariants.sh).
   # Pre-flight prune+fetch+ff-merge, .zskills-tracked write, and .worktreepurpose
   # write are all owned by the script; do NOT duplicate them here.
   ```

   Cherry-pick mode: one worktree per phase, auto-named branch, `/tmp/` path.
   After landing (cherry-pick to main), worktree is removed.

2. **Dispatch implementation agent WITHOUT `isolation: "worktree"`.** The
   prompt tells the agent the worktree path and requires absolute paths:

   **Before dispatching any Agent:** check `agents.min_model` in
   `.claude/zskills-config.json`. If set, use that model or higher
   (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch with a
   lower-ordinal model than the configured minimum.

   ```
   You are working in worktree: $WORKTREE_PATH

   IMPORTANT: Use ABSOLUTE PATHS for all file operations.
   - Bash: run `cd $WORKTREE_PATH` before commands
   - Read/Edit/Write/Grep: use $WORKTREE_PATH/... paths
   Do not work in any other directory.
   ```

   **Hygiene constraint — NEVER commit ephemeral pipeline files.** The
   files `.worktreepurpose`, `.zskills-tracked`, and `.landed` are worktree
   lifecycle markers and must stay UNTRACKED throughout the run.

   Test output lives OUTSIDE the worktree, at `/tmp/zskills-tests/<worktree-
   basename>/` (see CLAUDE.md). The filenames `.test-results.txt` and
   `.test-baseline.txt` should NEVER appear in the worktree at all; if they
   do, a stale writer leaked them, and `.claude/skills/commit/scripts/land-phase.sh` treats any
   git-tracked version as a landing-time error (a canary for contract
   violations — not a normal-path cleanup).

   Do NOT include any of these files in `git add` when dispatching
   implementation or verification agents. When staging for a commit, name
   specific source files explicitly (`git add skills/X.md tests/Y.sh ...`)
   rather than patterns that could sweep ephemerals in. `.claude/skills/commit/scripts/land-phase.sh`
   expects the lifecycle markers to be untracked and will refuse to clean up a
   worktree that has any of them tracked — a staged-delete left over
   from a commit would block `git worktree remove` and leak zombies.

   **Failed-run cleanup:** If a phase fails terminally, write `.landed` with
   `status: failed` in the worktree before invoking the Failure Protocol. The
   cron preamble runs `git worktree prune` to clean up stale entries from
   container restarts or crashed runs.

3. **Agent prompt MUST include the verbatim plan text.** The implementing
   agent receives the EXACT text of the phase from the plan file — not a
   summary, not bullet points extracted from it, not "implement the mechanical
   domain." The full section with every requirement, formula, constraint,
   design note, and acceptance criterion.

   **The plan is the spec.** If the agent doesn't have the verbatim text,
   it will guess, and it will guess wrong.

   **For plan sections longer than ~100 lines:** write the verbatim text to
   a temp file (e.g., `/tmp/phase-text.md`) and tell the agent to `Read`
   the file. This avoids the natural LLM tendency to compress long text
   when inlining it in a prompt. Shorter sections can be inlined directly.

4. **If dispatching sub-agents for parallel work items**, each sub-agent gets:
   - The **full phase context** (verbatim) — so they understand the big picture
   - Their **specific scope** clearly delineated — e.g., "you are implementing
     Mass, Spring, Damper. Another agent is implementing sensors and force
     source."
   - **What parallel agents are doing** — enough to avoid conflicts (shared
     files, shared infrastructure) but not so much detail that it confuses
     their scope. Format: "Another agent is handling: [list of items]. You
     should not modify [shared files] until that work lands."
   - **Shared infrastructure dependencies** — if a base class or domain
     definition must exist first, that must be built sequentially before
     dispatching parallel agents. Never dispatch parallel agents that both
     need to create the same file.

5. **Within-phase parallelism is the agent's judgment call** — if items are
   independent (e.g., Mass, Spring, Damper components), the agent may dispatch
   sub-agents. If there's shared infrastructure to build first, it works
   sequentially then parallelizes. The skill does NOT force parallelism.

6. **Commit discipline:**
   - One logical unit per commit — clean git history
   - `$FULL_TEST_CMD` before every commit (resolved from config — see argument-detection section)
   - Tests alongside implementation, not deferred to later
   - The implementation agent does NOT commit. The verification agent runs the full test suite and commits if verification passes. This ensures the hook's test gate is satisfied (the committing agent's transcript contains the test command).
   - **Declare pipeline ID** early in execution (before any git operation):
     ```bash
     echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"
     ```
     This echo is read by the tracking hook from the session transcript to
     scope marker checks to this pipeline. Uses last-match so re-invocations
     in the same session work correctly.
   - **Before dispatching any worktree agent**, write `.zskills-tracked` in the worktree:
     ```bash
     printf '%s\n' "run-plan.$TRACKING_ID" > "<worktree-path>/.zskills-tracked"
     ```
     Where `$TRACKING_ID` is the plan slug (e.g., `thermal-domain`). This file associates the worktree agent with this pipeline for hook enforcement.
   - **Rebase onto current main before final commit:**
     ```bash
     git fetch origin main && git rebase origin/main
     ```
     This ensures the commit contains only the agent's changes, not stale
     copies of files other agents already fixed on main. If rebase
     conflicts, abort (`git rebase --abort`) and proceed — the cherry-pick
     verification will catch stale files via selective extraction.

7. **Running tests in worktrees — CRITICAL.** Agents waste hours getting
   tests working in worktrees without these instructions. Include this
   VERBATIM in every implementation and verification agent prompt:

   > **Worktree test recipe:**
   >
   > **CRITICAL — Bash tool timeout:** when invoking `$FULL_TEST_CMD` via
   > the `Bash` tool, **pass `timeout: 600000`** (10 minutes). The default
   > 120000ms (2 min) is shorter than the suite's actual runtime (~3-4
   > min in zskills) and causes the Bash call to time out. **Do NOT
   > recover by retrying with `run_in_background: true` + `Monitor` /
   > `BashOutput` polling** — wake events for background processes do
   > not reliably deliver to subagents (you are a subagent), so the wait
   > never returns and the dispatch hangs at "Tests are running. Let me
   > wait for the monitor." Past failure: 6+ subagent crashes with
   > exactly that phrase across 2026-04-29 and 2026-04-30 sessions.
   > Always foreground-Bash with explicit long timeout; capture to file
   > as below; read the file when the call returns.
   >
   > 1. Start a dev server FIRST: `$DEV_SERVER_CMD &`
   > 2. Wait for it: `sleep 3`
   > 3. Run tests with output captured to a file (`Bash` tool with
   >    `timeout: 600000`):
   >    ```bash
   >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   >    mkdir -p "$TEST_OUT"
   >    $FULL_TEST_CMD > "$TEST_OUT/$TEST_OUTPUT_FILE" 2>&1
   >    ```
   >    **Never pipe** through `| tail`, `| head`, `| grep` — it loses
   >    output and forces re-runs. Capture once, read the file.
   > 4. The dev server must stay running for E2E tests. If source files
   >    changed (they will have — you're implementing), E2E tests FAIL
   >    (not skip) without a dev server.
   > 5. If tests fail, **read `"$TEST_OUT/$TEST_OUTPUT_FILE"`** to find the failures.
   >    Then run ONLY the failing test file to iterate on the fix:
   >    `node --test tests/the-failing-file.test.js`
   >    Do NOT re-run `$FULL_TEST_CMD` to diagnose — that wastes
   >    minutes when the single file takes 30 seconds.
   > 6. After fixing, run the single file again to confirm. Then run
   >    ```bash
   >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   >    mkdir -p "$TEST_OUT"
   >    $FULL_TEST_CMD > "$TEST_OUT/$TEST_OUTPUT_FILE" 2>&1
   >    ```
   >    ONE more time as the final gate before committing.
   > 7. Max 2 fix attempts at the same error — do not thrash.
   > 8. If a test fails in code you didn't touch, it may be pre-existing.
   >    See `/verify-changes` Phase 3 for the pre-existing failure protocol.

8. **No steps skipped or deferred.** If the plan says "implement 7 components,"
   implement 7 components. If it says "write tests for free vibration," write
   those exact tests. Do not stop after the easy items and declare the hard
   ones "future work."

### Plan-text drift signals

Include this VERBATIM in every implementation-agent prompt (worktree
mode) so the agent flags numeric acceptance bands that don't match
reality at execution time:

> If during your work you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

Tokens are parsed by `.claude/skills/run-plan/scripts/plan-drift-correct.sh --parse <report-file>`
in Phase 3.5. Format is single-line, space-delimited; `<field>` MUST NOT
contain `:` or `=`. Phase format: `phase=1`, `phase=4A`, etc.; bullet is
the 1-indexed ordinal of a numeric-bearing bullet within the phase's
`### Acceptance Criteria` section.

### PR mode (Phase 2)

When `LANDING_MODE == pr`, the orchestrator creates a persistent worktree with
a named feature branch. All phases accumulate on the same branch (one PR per
plan). The worktree persists across cron turns for chunked execution.

**Mixed mode validation:** When `LANDING_MODE` is `pr`, scan the current phase text:
- `### Execution: direct` → ERROR: "Mixed execution modes not allowed in PR
  plans. All phases must use worktree or delegate mode."
- `### Execution: delegate ...` → OK (delegate manages its own isolation)
- `### Execution: worktree` or no directive → OK (default)

**Branch naming:** `{branch_prefix}{plan-slug}`
- `branch_prefix` from config (`execution.branch_prefix`), default `"feat/"`
- `plan-slug` derived from plan file path: lowercase, hyphens, no extension
  - `plans/THERMAL_DOMAIN.md` → `thermal-domain`
  - `plans/ADD_FILTER_BLOCK.md` → `add-filter-block`

```bash
# Derive plan slug
PLAN_FILE="plans/THERMAL_DOMAIN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')

BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
FEATURE_BRANCH="$BRANCH_NAME"  # unified across modes — used by post-run-invariants.sh
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
```

**PR-mode bookkeeping rule:** in PR mode, orchestrator bookkeeping (tracker updates, plan reports, `PLAN_REPORT.md` regen, plan-frontmatter completion, mark-Done) commits **inside the worktree on the feature branch**, not on `main`. The feature branch is the single source of truth; the squash merge lands everything atomically on `origin/main`, keeping local `main` in lockstep. In cherry-pick/direct mode these commits stay on `main` as before. Every "commit on main" instruction below for bookkeeping must be read through this lens.

**Worktree creation — via `.claude/skills/create-worktree/scripts/create-worktree.sh`, NOT `isolation: "worktree"`:**

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Resume detection stays directory-based (R2-M1): an existing PR worktree
# means we're resuming the same plan across cron turns.
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing PR worktree at $WORKTREE_PATH"
else
  WORKTREE_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --prefix pr \
    --branch-name "$BRANCH_NAME" \
    --allow-resume \
    --purpose "run-plan PR mode; plan=${PLAN_SLUG}" \
    --pipeline-id "run-plan.${TRACKING_ID}" \
    "${PLAN_SLUG}")
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for PR mode" >&2
    exit "$RC"
  fi
fi
# create-worktree.sh owns pre-flight prune+fetch+ff-merge, the
# underlying safe add (with ZSKILLS_ALLOW_BRANCH_RESUME=1 set via
# --allow-resume), .zskills-tracked (from --pipeline-id), and
# .worktreepurpose writes.
```

**One branch per plan.** All phases accumulate on the same branch. The worktree
persists across cron turns for chunked execution. Do NOT create a new worktree
per phase.

**Dispatching agents to the worktree:** Dispatch agents WITHOUT
`isolation: "worktree"`. The agent's prompt tells it to work in the worktree:

```
Agent tool prompt:
  "You are implementing Phase N of plan X.
   FIRST: cd /tmp/myproject-pr-thermal-domain
   All work happens in that directory. Do not work in any other directory.

   <phase work items here>

   Commit rules:
   - Do NOT commit. The verification agent commits after review.
   - Stage specific files by name (not git add .)
   ..."
```

The key line is `FIRST: cd $WORKTREE_PATH` — the agent treats this as a
mandatory first action. Without `isolation: "worktree"`, the agent starts in
the main repo directory, so the `cd` instruction is essential.

**Test baseline capture (orchestrator practice):** Before dispatching the
implementation agent, the orchestrator captures a test baseline in the worktree:

```bash
# Resolve config-derived vars at fence-top — context compaction may have
# lost vars set in earlier fences (per the convention at modes/pr.md:325-345).
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"

# Orchestrator captures baseline BEFORE impl agent starts
cd "$WORKTREE_PATH"
if [ -n "$FULL_TEST_CMD" ]; then
  TEST_OUT="/tmp/zskills-tests/$(basename "$WORKTREE_PATH")"
  mkdir -p "$TEST_OUT"
  $FULL_TEST_CMD > "$TEST_OUT/.test-baseline.txt" 2>&1 || true
fi
```

### Post-implementation tracking

After the implementation agent finishes (whether worktree or delegate mode),
create the implementation step marker:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.implement"
```

### Pre-verification tracking

The `requires.verify-changes.$TRACKING_ID` marker was created at skill
entry (Phase 1 step 8). The hook is enforcing it. Pass the tracking ID to
the verification agent so it can create its own fulfillment marker.

> **Note:** The per-pipeline verification requirement
> (`requires.verify-changes.$TRACKING_ID`) is **distinct** from
> `requires.verify-changes.final.<META_PLAN_SLUG>` which is a cross-branch
> final verification marker with a different lifecycle — created by
> `/research-and-go` Step 0, fulfilled after ALL sub-plans complete. Phase A
> does not modify or consolidate this marker; the two coexist independently.

Pass the tracking ID to the verification agent in the dispatch prompt so it
can create its own fulfillment marker:
> Your tracking ID is `$TRACKING_ID`. On entry, create
> `fulfilled.verify-changes.$TRACKING_ID` in the main repo's
> `.zskills/tracking/` directory.

## Phase 3 — Verify (separate agent)

Critical: the verification agent is NOT the implementing agent. Fresh eyes
catch implementer blindspots — deferred hard parts, missing tests, stubs,
shortcuts.

### Dispatch protocol

**Check your tool list.** If `Agent` (or `Task`) is in your tool list,
you are at top level — dispatch a fresh verification subagent per the
protocol below. The implementation subagent (in its worktree) and the
verification subagent are sibling subagents of you, the top-level
orchestrator. The verifier has independent context from the implementer.

**If you do NOT have the `Agent` tool**, you are running as a subagent
yourself (Claude Code subagents have no Agent tool, by Anthropic's
design at https://code.claude.com/docs/en/sub-agents). Run `/verify-changes
worktree` inline in your current context — the verifier subagent (you)
is fresh relative to the implementer subagent that ran in a separate
context. This fallback is mostly defensive since /run-plan typically runs
at top level.

**Agent timeout: 45 minutes.** Verification should take 15-30 minutes —
reading diffs, running tests, checking acceptance criteria. If a verification
agent hasn't returned after 45 minutes, it is thrashing (likely on test
setup or repeated test failures). Declare it **failed** and invoke the
Failure Protocol. Do NOT let verification agents run indefinitely — they
are the most common source of time waste.

### Delegate mode verification

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"` (same agent definition as worktree mode — `.claude/agents/verifier.md`). The Layer 3 invocation block (`### Failure Protocol — verifier response validation` below) applies identically: pipe the verifier's response through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"` immediately after the dispatch returns; on `VALIDATE_EXIT=1` OR 45-min timeout, emit the verbatim STOP message and halt the pipeline.

If this phase used delegate execution, verification runs on **main**:

1. **Verify commits landed** — check `git log --oneline -10` for the
   delegate's commits. If expected commits are missing, the delegate
   failed to land — invoke Failure Protocol.
2. **Run `$FULL_TEST_CMD` on main** (resolve via
   `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
   if not already in environment) — the delegate already tested, but
   /run-plan verifies against the plan's acceptance criteria.
3. **Check acceptance criteria** from the verbatim plan text — the delegate
   skill doesn't know the plan's criteria, only /run-plan does.
4. Dispatch a verification agent if needed (same rules as worktree mode
   below, but targeting main instead of a worktree path).

#### Plan-text drift signals (delegate mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> If during your verification you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

**Verifiers MUST re-detect drift independently.** Do not forward the
implementation agent's tokens — re-measure each numeric acceptance
criterion against current reality. If implementation skipped the check
OR implementation IS the source of drift, the verifier catches it.
Phase 3.5 processes the UNION of both reports' tokens.

#### Smoke-procedure revert mechanics (delegate mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> Many plan ACs include manual smoke procedures: temporarily modify a
> file under test → run a script → confirm a behavior change → revert
> the throwaway. When you revert, **first check whether the file has
> uncommitted changes**: `git status -s <file>`. A line beginning with
> ` M`, `MM`, `AM`, or any other dirty-state marker means uncommitted
> impl work is present.
>
> - **Uncommitted: DO NOT use `git checkout <file>`.** It reverts to
>   HEAD, which is the pre-implementation state — silently wiping the
>   implementer's uncommitted work. /run-plan's design contract is
>   "implementer writes, verifier commits"; the file you're
>   smoke-testing typically has uncommitted impl changes. Use Edit to
>   remove the specific throwaway lines you added, or save+restore
>   with `cp <file> /tmp/$(basename <file>).pre-smoke` and
>   `cp /tmp/$(basename <file>).pre-smoke <file>` (basename avoids
>   creating nested /tmp paths that don't exist for relative paths
>   with subdirectories).
> - **Clean (no uncommitted changes)**: `git checkout <file>` is safe
>   and reverts only your throwaway.
>
> This guidance applies to **mid-smoke reverts only**. Post-failure
> rollbacks (e.g., Phase 3.5 plan-file rollback) run after something
> has gone wrong on files that should match HEAD — `git checkout` is
> correct there.
>
> If you suspect the file under test has been clobbered (file size
> drops, expected lines vanish), STOP. Do NOT reconstruct from the
> spec — even if you re-run every AC against the reconstruction, the
> orchestrator cannot validate that your reconstruction matches the
> implementer's actual intent. Invoke the Failure Protocol so the
> orchestrator can re-dispatch implementation cleanly against a
> known-clean baseline.

### Worktree mode verification

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The verifier agent definition lives at `.claude/agents/verifier.md` — `tools: Read, Grep, Glob, Bash, Edit, Write`; frontmatter PreToolUse hook (`inject-bash-timeout.sh`) auto-extends every Bash call's timeout to 600000 ms (10 min) so the bg+Monitor recovery reflex never engages. The verifier CANNOT dispatch sub-subagents — fix-agent dispatch (Phase 3 step 3 "fresh fix agent") stays at the orchestrator level. If the dispatch returns "no such agent" or equivalent, the verifier agent file is missing — STOP and run `/update-zskills` (Phase 5 of the verifier-agent-fix plan teaches it to install `.claude/agents/verifier.md`).

1. **Dispatch verification agent** targeting the worktree's changes. The
   verification agent is dispatched with `subagent_type: "verifier"` and
   **without** `isolation: "worktree"` — the
   Agent tool's `isolation` parameter creates a NEW worktree, it cannot attach
   to an existing one.

   **Before dispatching:** check `agents.min_model` in `.claude/zskills-config.json`.
   If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never
   dispatch with a lower-ordinal model than the configured minimum.

   Give the verification agent:
   - The **worktree path** from Phase 2 (so it can read files and run tests
     there). The verifier must run tests via:

     ```bash
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
     cd <worktree-path>
     TEST_OUT="/tmp/zskills-tests/$(basename "<worktree-path>")"
     mkdir -p "$TEST_OUT"
     $FULL_TEST_CMD > "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" 2>&1
     ```

     The orchestrator substitutes `$FULL_TEST_CMD` in the prompt with the
     config-resolved literal command BEFORE dispatching the agent — the
     verifier never resolves it themselves (don't let them search the repo).
     If `TEST_MODE=skipped`, dispatch this block with the instruction
     "Do NOT run tests; report `Tests: skipped — no test infra` in your
     verification report" instead of the bash block above.

     Note: compute `$TEST_OUT` from the worktree-path LITERAL you were handed,
     NOT from `$(pwd)` at prompt-entry time — the orchestrator dispatches you
     without `isolation`, so your initial cwd is the orchestrator's (typically
     main), and a pre-cd `$(pwd)` would yield the wrong basename and miss the
     baseline.

     Orchestrator-runtime note: when the orchestrator constructs the verifier
     prompt, it substitutes the literal string `<worktree-path>` with the
     actual worktree path BEFORE dispatching. The verifier sees a fully-
     substituted prompt — no placeholder parsing on its side. Both orchestrator
     baseline capture (line 811) and verifier `$TEST_OUT` derivation MUST use
     `basename` of the SAME path literal, so the baseline and the results land
     in the same `/tmp/zskills-tests/<name>/` bucket.

   - The **worktree branch name** (so it can diff against main:
     `git diff main...<branch>`)
   - The **verbatim phase text** from the plan (same text the implementer got)
   - Instruction to run `/verify-changes worktree` — the verification agent
     runs this, NOT you. Do NOT run verification yourself — you are the
     orchestrator with implementer bias.
   - The **work items checklist** — verify each item was actually implemented,
     not stubbed or skipped
   - The **`"$TEST_OUT/.test-baseline.txt"` file** captured before implementation
     started (if `FULL_TEST_CMD` is configured). The verification agent should:
     - Read `"$TEST_OUT/.test-baseline.txt"` (baseline captured before implementation)
     - Compare against `"$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}"` (results after running tests now)
     - **New failures** (in results but not in baseline) → regressions, must
       be fixed before the phase can commit
     - **Pre-existing failures** (in both baseline and results) → note in report,
       do not fix (these predate this phase)
     - **Resolved failures** (in baseline but not in results) → note positively
       as improvements
     - If `"$TEST_OUT/.test-baseline.txt"` is absent (`FULL_TEST_CMD` not configured),
       treat all failures as potentially new — report all of them

2. **Additional plan-specific checks** (the verifier checks these against the
   verbatim plan text — not against a summary):
   - Do commits cover ALL work items listed in the plan? Any missing?
   - Does implementation follow the plan's stated approach? (e.g., "use
     internal displacement state for Spring" — did it actually do that?)
   - Are constraints respected? (no external solvers, etc.)
   - Any deferred hard parts, stubs, TODOs, or placeholder implementations?
   - Do acceptance criteria match? (e.g., "test free vibration x(t) = A cos(wt)"
     — does that exact test exist with that exact formula?)

   **"Noted as gap" is a verification FAILURE.** If any work item, acceptance
   criterion, or checklist item was skipped and merely noted — that is not a
   pass. It is a fail. The verifier must not rationalize skipped steps as
   "not blockers" or "gaps for future work." If the plan says to do it and
   it wasn't done, verification fails. Period.

   Past failure: Block Expansion Plan Phase 1 — the implementer skipped the
   example model (Step 7 of `/add-block`) and runtime entry (Step 10). The
   verifier saw both skips but wrote "gaps noted" instead of invoking the
   Failure Protocol. The phase was reported as complete with missing work.

3. **If verification fails:**
   - Without `auto`: present findings, ask user what to do
   - With `auto`: dispatch a **fresh fix agent** for the missing items.
     The fix agent receives: the worktree path, the verbatim plan text,
     the specific items that failed verification, and instructions to
     complete them — not summarize them, not note them, COMPLETE them.
     If the missing item is an example model, the fix agent calls
     `/add-example`. If it's a runtime entry, the fix agent adds it.
     The fix agent is NOT the implementer — it's a fresh agent with no
     bias toward "this is good enough."

     **Dispatcher: the orchestrator (top-level `/run-plan`), not the verifier subagent.** The verifier's tool allowlist excludes `Agent`; sub-subagent dispatch is categorically unavailable per https://code.claude.com/docs/en/sub-agents. The verifier reports failed-AC findings back; the orchestrator dispatches the fresh fix agent.

     After the fix agent finishes, re-verify (max 2 rounds). If still
     failing after 2 fix+verify cycles, **STOP** — needs human judgment.
     Invoke the Failure Protocol.

### Failure Protocol — verifier response validation

**Failure Protocol — verifier response validation (Layer 3).**

**Detection runs immediately after the verifier `Agent` dispatch returns**, before any tracker write or commit:

```bash
printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
VALIDATE_EXIT=$?
```

The script (sourced from `hooks/verify-response-validate.sh` at zskills source; installed by `/update-zskills` Step C) checks:
- **Stalled-string trigger** — case-insensitive substring match of any of 7 whitelisted phrases against the LAST 10 LINES of the response (`let me wait for the monitor`, `tests are running. let me wait`, `monitor will signal`, `monitor to signal`, `still searching. let me wait`, `waiting on bashoutput`, `polling bashoutput`).
- **Min-byte threshold** — response < 200 bytes is treated as empty/stub.

Exit 0 = PASS (proceed to tracker write + commit). Exit 1 = FAIL — read stderr to see which pattern or threshold fired.

**AND** detect agent-timeout-exceeded: if the dispatch took longer than 45 minutes (existing rule, line ~1275-1280), treat as failed.

**On detection (`VALIDATE_EXIT=1` OR timeout):** STOP. Do NOT write the verification step marker. Do NOT proceed to Phase 3.5 plan-drift correction. Do NOT proceed to Phase 4 commit. Emit the verbatim STOP message:

```
STOP: verifier returned without meaningful results.

$(cat /tmp/last-validate-stderr)

This is a verification FAIL, not a routing decision.

Failure Protocol:
1. Roll back any uncommitted phase work in <worktree-path>
   (git status; user-driven cleanup).
2. Tracker entry: requires.verify-changes.<TRACKING_ID> stays unfulfilled.
3. If you just installed the verifier agent (this is the first
   dispatch of the session post-install), restart Claude Code (or
   open a new session) before re-dispatching — `.claude/agents/`
   is auto-discovered ONLY at session start (per
   code.claude.com/docs/en/sub-agents priority table). There is
   no in-session reload command; `/agents reload` does not exist.
4. Halt the pipeline. Do not auto-retry. Re-dispatch only after
   surfacing the failure and confirming the verifier agent file is
   installed (.claude/agents/verifier.md exists; bash
   $CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh < /dev/null
   exits 0).
```

**Inline self-verification is NOT acceptable recovery.** Per CLAUDE.md ## Verifier-cannot-run rule.

**No automatic re-dispatch.** Re-dispatching with the same agent type hits the same wall.

#### Plan-text drift signals (worktree mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> If during your verification you observe a plan's acceptance criterion
> contains a numeric target (lines / tests / cases / commits / files)
> that doesn't match reality, emit a line of the form:
>
> ```
> PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
> ```
>
> in your final report. One per drift. Advisory — continue your work.

**Verifiers MUST re-detect drift independently.** Do not forward the
implementation agent's tokens — re-measure each numeric acceptance
criterion against current reality. If implementation skipped the check
OR implementation IS the source of drift, the verifier catches it.
Phase 3.5 processes the UNION of both reports' tokens.

#### Smoke-procedure revert mechanics (worktree mode verification)

Include this VERBATIM in the verifier dispatch prompt:

> Many plan ACs include manual smoke procedures: temporarily modify a
> file under test → run a script → confirm a behavior change → revert
> the throwaway. When you revert, **first check whether the file has
> uncommitted changes**: `git status -s <file>`. A line beginning with
> ` M`, `MM`, `AM`, or any other dirty-state marker means uncommitted
> impl work is present.
>
> - **Uncommitted: DO NOT use `git checkout <file>`.** It reverts to
>   HEAD, which is the pre-implementation state — silently wiping the
>   implementer's uncommitted work. /run-plan's design contract is
>   "implementer writes, verifier commits"; the file you're
>   smoke-testing typically has uncommitted impl changes. Use Edit to
>   remove the specific throwaway lines you added, or save+restore
>   with `cp <file> /tmp/$(basename <file>).pre-smoke` and
>   `cp /tmp/$(basename <file>).pre-smoke <file>` (basename avoids
>   creating nested /tmp paths that don't exist for relative paths
>   with subdirectories).
> - **Clean (no uncommitted changes)**: `git checkout <file>` is safe
>   and reverts only your throwaway.
>
> This guidance applies to **mid-smoke reverts only**. Post-failure
> rollbacks (e.g., Phase 3.5 plan-file rollback) run after something
> has gone wrong on files that should match HEAD — `git checkout` is
> correct there.
>
> If you suspect the file under test has been clobbered (file size
> drops, expected lines vanish), STOP. Do NOT reconstruct from the
> spec — even if you re-run every AC against the reconstruction, the
> orchestrator cannot validate that your reconstruction matches the
> implementer's actual intent. Invoke the Failure Protocol so the
> orchestrator can re-dispatch implementation cleanly against a
> known-clean baseline.

### Post-verification tracking

After verification passes, create the verification step marker:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\nresult: pass\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.verify"
```

## Phase 3.5 — Detect and auto-correct plan-text drift

Runs AFTER Phase 3's `### Post-verification tracking` writes
`step.run-plan.$TRACKING_ID.verify`, and BEFORE Phase 4's tracker
commit. Reads both the implementation agent's and verification
agent's reports for `PLAN-TEXT-DRIFT:` tokens and auto-corrects
the plan file.

### 1. Gather reports

Concatenate the implementation agent's final-message text and the
verification agent's final-message text into a single parse input.
Both agents' outputs are available from Phase 2 and Phase 3 agent
dispatches.

### 2. Parse tokens

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/plan-drift-correct.sh" --parse <combined-reports>
```
Produces one `<phase>|<bullet>|<field>|<stated>|<actual>` line per
drift. Zero lines = no drifts → skip to step 6.

### 3. Per-drift decision

For each record, compute drift via:
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/plan-drift-correct.sh" --drift "<stated>" "<actual>"
```
Decision table:

| Drift | Byte-preservation / test gate | Action |
|-------|-------------------------------|--------|
| ≤10%  | held                          | auto-correct + count |
| 10-20% | held                         | auto-correct + count + note in phase report |
| >20%  | held                          | ABORT: do NOT correct, report to user, escalate to Failure Protocol (plan intent likely wrong, not just arithmetic) |
| any   | failed                        | Failure Protocol (byte-preservation failure always escalates) |
| unsupported `<stated>` form (exit 2) | — | skip, log as "non-derivable" in phase report |

### 4. Auto-correct

For each "auto-correct" record:
```bash
NEW_BAND="$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/plan-drift-correct.sh" --drift-band <actual> 5)"  # ±5% of actual
bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/plan-drift-correct.sh" --correct <plan-file> <phase> <bullet> "$NEW_BAND" --audit "was <stated>"
```
`--audit` appends `<!-- Auto-corrected YYYY-MM-DD: was <stated>, arithmetic says <actual> -->` inline on the bullet.

### 5. Marker ordering and failure handling

`.verify` is ALREADY written by Phase 3. That satisfies the hook's
landing gate (`hooks/block-unsafe-project.sh.template:341 etc.`
globs `step.*.verify`). If Phase 3.5 proceeds cleanly, write an
informational marker:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ndrifts_found: %s\ndrifts_corrected: %s\ndrifts_escalated: %s\ncompleted: %s\n' \
  "$PHASE" "$FOUND" "$CORRECTED" "$ESCALATED" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.drift-detect"
```
Uses the `phasestep.*` prefix (informational; hook ignores). The
`step.*.verify` marker stays as-is.

If Phase 3.5 fails (e.g., `.claude/skills/run-plan/scripts/plan-drift-correct.sh` exits
non-zero mid-correction, or >20% drift case triggers), the
orchestrator MUST:
1. `git checkout -- <plan-file>` to revert any partial corrections.
2. DELETE `step.run-plan.$TRACKING_ID.verify` (so the landing gate
   re-blocks — the pipeline is no longer verified-and-clean, it's
   verified-but-drift-escalated).
3. Write `phasestep.run-plan.$TRACKING_ID.$PHASE.drift-fail` with
   the error detail.
4. Invoke Failure Protocol.

### 6. Commit-location rule

The auto-correction edits the plan file. Where does the edit commit?

**Cherry-pick / direct mode:** commit on main, bundled with Phase 4's
tracker commit. Combined message:
```
chore: mark phase <name> in progress (+ auto-corrected <N> stale acceptance bands)
```
If N == 0: default Phase 4 message.

**PR mode:** commit inside the worktree on the feature branch,
bundled with Phase 4's feature-branch tracker commit. Same combined
message. The next phase's Phase 1 parse reads the plan file from
the worktree (since `finish auto` PR-mode runs consecutive phases
in the SAME worktree), so the corrected band is visible to the next
phase's thrash-detection.

### 7. Thrash rule

If the SAME `<phase>+<bullet>` pair gets a `PLAN-TEXT-DRIFT:` token
on a subsequent Phase 3.5 invocation (across phases in the same
`/run-plan finish auto` execution), the first correction was
wrong. ABORT:
1. Write `phasestep.*.drift-fail` with "thrash detected: phase
   P bullet B re-flagged after correction."
2. Do NOT correct a second time.
3. Invoke Failure Protocol.

Thrash rule is scoped to the current `/run-plan` invocation's
history, NOT across sessions. State is tracked in-memory by the
orchestrator during `finish auto`; for cron-fired chunked runs,
the rule relies on re-reading the plan file from the correct
location (worktree for PR mode, main for cherry-pick / direct).

### 8. Interaction with /refine-plan

Phase 3.5 corrects small arithmetic drift only. If the scan finds
multiple fields with >10% drift OR the plan's own extraction rules
are arithmetically inconsistent (detected by the pre-dispatch gate
in Phase 1 step 6), append a recommendation to the phase report:
"Recommend running `/refine-plan <plan-file>` after close-out; this
plan has structural drift beyond per-band correction scope."

Do NOT auto-dispatch `/refine-plan` mid-run — too expensive and
scope-overlapping.

## Phase 4 — Update Progress Tracking

After verification passes. The plan file tracks progress across phases — an
orchestrator concern, not an implementation artifact. Update it promptly so
the next cron invocation sees the correct phase status and advances
(preventing infinite loops).

> If Phase 3.5 auto-corrected any acceptance bands, those edits are
> staged alongside the tracker update here and land as a single
> commit.

**Commit location depends on `LANDING_MODE`** (see PR-mode bookkeeping rule):
cherry-pick/direct commits on main; PR mode `cd "$WORKTREE_PATH"` first and
commits on the feature branch.

1. **Update the plan file's progress tracker on main** — change the phase
   status to Done with the commit hash (from worktree branch or delegate's
   landed commits) and notes. Examples
   by format:
   - Table: `| **4b: Mechanical** | ✅ Done | \`abc1234\` | 7 components, 45 tests |`
   - Checklist: `- [x] Phase 4b — Mechanical Domain (abc1234, 7 components)`
   - Section: add `**Status:** ✅ Done (abc1234)` to the section header

2. **Update companion progress doc on main** if one exists — add
   implementation details, architecture notes, lessons learned

3. **If no tracker exists:**
   - Interactive mode: suggest adding one to the plan file, ask user
   - Auto mode: note in the report that no tracker was updated

4. **Mark the phase as 🟡 In Progress and commit** (mode-conditional location):
   ```bash
   # PR mode only: cd "$WORKTREE_PATH" first (cherry-pick/direct: stay on main)
   git add <plan-file> [companion-doc]
   git commit -m "chore: mark phase <name> in progress"
   ```
   Not ✅ Done yet — Phase 6 updates to Done after landing succeeds (in
   cherry-pick/direct via a main commit, in PR mode via a commit on the
   feature branch *before* push so it's captured in the squash). If
   landing fails in either mode, tracker correctly reads In Progress.

5. **(PR mode only) Sync the GitHub PR body's progress section.** The PR
   body was snapshotted at PR-open time in Phase 6 (Step 5, Create PR) and
   wrapped with HTML-comment markers (`<!-- run-plan:progress:start -->`
   and `<!-- run-plan:progress:end -->`). As subsequent phases land on the
   feature branch, the PR body must be updated so readers see current
   progress — not the stale Phase 1 snapshot. Splice ONLY the
   marker-enclosed region; preserve user-authored prose outside the
   markers verbatim.

   Skip this step entirely in cherry-pick / direct modes — there is no PR.
   Skip this step in PR mode if no PR exists yet (Phase 6 hasn't opened
   one), e.g. when Phase 4 runs between phases in finish mode before any
   push has happened. Phase 6's Create PR step is authoritative for the
   initial body.

   ```bash
   # Only run in PR mode, and only if a PR already exists for this branch.
   if [ "$LANDING_MODE" = "pr" ]; then
     PR_NUMBER=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
     if [ -n "$PR_NUMBER" ]; then
       # Capture current PR body to a temp file (per-PR path avoids cross-run
       # collisions). Use gh's --jq to extract the JSON string cleanly; this
       # yields raw markdown with real newlines (no JSON escaping).
       PR_BODY_FILE="/tmp/pr-body-${PLAN_SLUG}-${PR_NUMBER}.md"
       if ! gh pr view "$PR_NUMBER" --json body --jq '.body' > "$PR_BODY_FILE" 2>/dev/null; then
         echo "NOTICE: skipping PR body sync: gh pr view #$PR_NUMBER failed" >&2
       else
         CURRENT_BODY=$(cat "$PR_BODY_FILE")
         START_MARKER='<!-- run-plan:progress:start -->'
         END_MARKER='<!-- run-plan:progress:end -->'

         # Regenerate the progress section from the plan tracker — SAME
         # format as Phase 6 (Step 5) writes at PR-open time. Keep this in
         # sync with that template.
         COMPLETED_PHASES=$(grep -E '^\| .* \| ✅' "$PLAN_FILE" | sed 's/|//g' | awk '{$1=$1};1' || echo "See plan file")
         NEW_PROGRESS="**Phases completed:**
$COMPLETED_PHASES"

         # Splice with bash regex (NO jq — zskills avoids jq in skills).
         # The regex captures: (prefix-up-to-and-including-start-marker)
         # (anything-in-between) (end-marker-and-rest). We keep groups 1
         # and 3 and replace group 2 with the new progress content.
         # Graceful on missing markers: emit NOTICE and skip the update.
         if [[ "$CURRENT_BODY" =~ (.*$START_MARKER)(.*)($END_MARKER.*) ]]; then
           PREFIX="${BASH_REMATCH[1]}"
           SUFFIX="${BASH_REMATCH[3]}"
           UPDATED_BODY="${PREFIX}
${NEW_PROGRESS}
${SUFFIX}"
           if ! gh pr edit "$PR_NUMBER" --body "$UPDATED_BODY" >/dev/null 2>&1; then
             echo "WARNING: gh pr edit #$PR_NUMBER failed — PR body not synced (auth/network?)" >&2
           else
             echo "Synced PR #$PR_NUMBER body progress section."
           fi
         else
           echo "NOTICE: skipping PR body sync: markers not found; this is expected for PRs not opened by /run-plan PR mode" >&2
         fi
         rm -f "$PR_BODY_FILE"
       fi
     fi
   fi
   ```

   **Design properties:**
   - **Idempotent:** the splice only rewrites the marker-enclosed region;
     safe to run multiple times per phase.
   - **Headless-safe:** no interactive prompts; operates via `gh pr view`
     + `gh pr edit`.
   - **Preserves user edits outside markers:** user-authored prose
     (additional sections, links, review notes) outside the marker pair
     survives the splice.
   - **Graceful on missing markers:** emit a NOTICE to stderr and skip
     the update. Do NOT fail Phase 4 — the plan-tracker commit on the
     feature branch is the source of truth; the PR body is a convenience
     surface.
   - **No jq:** splice is pure bash regex (`BASH_REMATCH`). `gh pr view
     --json body --jq '.body'` is used only to extract the JSON string
     cleanly (`.jq` is a flag on `gh`, not a separate binary dep).

## Phase 5 — Write Report

**PREPEND** new phase sections after the H1 in `reports/plan-{slug}.md`
(`{slug}` from plan filename, e.g., `FEATURE_PLAN.md` → `plan-physics module`).
Newest phase at the top — the reader's question is "what needs my
attention?" and that's always the newest phase.

If the file doesn't exist, create it with a `# Plan Report — {plan name}`
heading. Never overwrite the file — each phase adds a section.

**File location and commit follow the PR-mode bookkeeping rule**: in PR
mode, write to `$WORKTREE_PATH/reports/plan-{slug}.md`, regenerate
`$WORKTREE_PATH/PLAN_REPORT.md`, and commit on the feature branch.
Cherry-pick/direct: write/regen/commit on main (unchanged).

After writing, regenerate `PLAN_REPORT.md` in the repo root as an **index**
of all plan reports:
1. Scan `reports/plan-*.md` files
2. For each: extract plan name, phase count, overall status, unchecked `[ ]`
3. Write index with Needs Sign-off section (linked items) + Plans table
4. Staleness rule: items >7 days flagged STALE

**Report format** — each phase gets one `## Phase` section:

```markdown
## Phase — 4b Translational Mechanical Domain [UNFINALIZED]

**Plan:** plans/FEATURE_PLAN.md
**Status:** Completed (verified)
**Worktree:** ../plan-physics module-4b
**Commits:** abc1234, def5678

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1 | Mass component | Done | abc1234 |
| 2 | Spring component | Done | def5678 |

### Verification
- Test suite: PASSED (4342 tests)
- Acceptance criteria: all met

### User Sign-off
{Only if UI files changed. Omit entirely for non-UI phases.}

- [ ] **P4b-1** — Variable viewer panel
  1. Open the app, load a physics module model (e.g., voltage-divider example)
  2. Run the simulation
  3. Click the lightning icon in the toolstrip
  4. Verify the Physical Variables panel opens with columns for V, I, P
  5. Check that values update after simulation completes
  ![viewer panel](.playwright/output/phase4b-variable-viewer.png)

- [ ] **P4b-2** — Toolstrip button
  1. Verify the lightning icon appears in the toolstrip
  2. Click it — panel should toggle open/closed
```

**Report format rules:**
- **One checkbox per item.** Do NOT use a summary table with `[ ]` AND a
  detail section with `[ ]` — the viewer counts both as separate checkboxes.
  Use only the checklist format above.
- **Phase-prefixed IDs** — `P4b-1`, `P2-3`, not `#1`, `#2` (which reset
  per phase and collide).
- **Include verification instructions** under each checkbox — numbered
  steps, screenshots. The reviewer needs to know what to do, not just
  what to check off.
- **One item per verifiable thing** — "3 check blocks in Block Explorer"
  is wrong. Each block gets its own checkbox.
- **Avoid literal `[ ]` in description text** — the viewer renders it as
  a phantom checkbox. Describe instead: "bracket pair" or use backtick
  escaping.

### Post-report tracking

After writing the report and regenerating the index, create the report step marker:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.report"
```

## Phase 5b — Plan Completion

Triggers when ALL phases are done: either the last phase just finished
(single-phase run where it was the only remaining phase), or in `finish`
mode after all phases complete. Run this BEFORE Phase 6 (Land).

### 0a. Idempotent early-exit

If frontmatter is already `status: complete`: this is a no-op re-entry.
Exit cleanly without re-committing. Output "Plan already complete (no-op)."

### 0b. Final-verify gate

**Only applies if a final-verify marker exists.** Check for the cross-branch
final-verify marker:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# The final-verify marker is written by /research-and-go into ITS pipeline
# subdir (research-and-go.$META_PLAN_SLUG/), not into this /run-plan's own
# subdir. Use glob-dual-lookup: prefer any research-and-go.*/ subdir whose
# marker basename matches this TRACKING_ID; fall back to the legacy flat
# path during the Phase 2-6 transitional window.
MARKER=$(ls "$MAIN_ROOT/.zskills/tracking/"research-and-go.*/requires.verify-changes.final."$TRACKING_ID" 2>/dev/null | head -1)
[ -z "$MARKER" ] && MARKER="$MAIN_ROOT/.zskills/tracking/requires.verify-changes.final.$TRACKING_ID"
FULFILLED=$(ls "$MAIN_ROOT/.zskills/tracking/"research-and-go.*/fulfilled.verify-changes.final."$TRACKING_ID" 2>/dev/null | head -1)
[ -z "$FULFILLED" ] && FULFILLED="$MAIN_ROOT/.zskills/tracking/fulfilled.verify-changes.final.$TRACKING_ID"
```

Three branches:

1. **Marker exists AND fulfilled missing**: defer pipeline completion until
   `/verify-changes branch` runs at top level. Use self-rescheduling pattern
   with exponential backoff.

   Rationale: `/verify-changes branch` can take 5–60 min depending on
   cumulative diff size; a fixed-time second cron risks firing before
   fulfillment exists, causing visible "still pending" turns.

   Read attempt counter file:
   `$MAIN_ROOT/.zskills/tracking/verify-pending-attempts.$TRACKING_ID`
   (numeric content; absent = 0). On each invocation:

   - Increment attempt counter, write back to file.
   - Compute backoff: `attempt 1: 10min, 2: 20min, 3: 40min, 4+: 60min`
     (capped at 60min).
   - On attempt 1 only: schedule the verify cron itself —
     `Run /verify-changes branch tracking-id=$TRACKING_ID` one-shot,
     ~5 min from now.
   - On every attempt: schedule re-entry cron —
     `Run /run-plan <plan-file> finish auto` one-shot, `<backoff>` from now.
   - Exit with message:
     > Final cross-branch verify pending (attempt <N>). Re-entry scheduled
     > in <backoff>. Verify cron: <id-if-attempt-1>. Re-entry cron: <id>.

   Do NOT run Phase 5b sub-steps 1–4. Do NOT run Phase 5c. Do NOT run
   Phase 6.

   ```bash
   # Self-rescheduling with exponential backoff
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   ATTEMPTS_FILE="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
   if [ -f "$ATTEMPTS_FILE" ]; then
     ATTEMPT=$(( $(cat "$ATTEMPTS_FILE") + 1 ))
   else
     ATTEMPT=1
   fi
   echo "$ATTEMPT" > "$ATTEMPTS_FILE"

   # Compute backoff minutes: 10, 20, 40, 60 (capped)
   case "$ATTEMPT" in
     1) BACKOFF_MIN=10 ;;
     2) BACKOFF_MIN=20 ;;
     3) BACKOFF_MIN=40 ;;
     *) BACKOFF_MIN=60 ;;
   esac
   ```

   On attempt 1, schedule the verify cron (~5 min from now) via the
   `.claude/skills/run-plan/scripts/compute-cron-fire.sh` helper. The helper handles +5 default
   margin, :00/:30 avoidance, and all minute/hour/day/month/year
   rollovers correctly (inlined bash versions previously got day+month
   rollover wrong — at 23:58, the naive math pinned the cron to
   earlier-today, and it would fire ~365 days out).
   ```bash
   VERIFY_CRON=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/compute-cron-fire.sh")
   ```
   Then call `CronCreate` with:
   - `cron`: `"$VERIFY_CRON"`
   - `recurring`: false
   - `prompt`: `"Run /verify-changes branch tracking-id=$TRACKING_ID"`

   On every attempt, schedule re-entry cron (`<backoff>` from now). Pass
   `--allow-marks` because the re-entry cadence is backoff-driven, not
   API-busy-avoidance-driven:
   ```bash
   REENTRY_CRON=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/compute-cron-fire.sh" --offset "$BACKOFF_MIN" --allow-marks)
   ```
   Then call `CronCreate` with:
   - `cron`: `"$REENTRY_CRON"`
   - `recurring`: false
   - `prompt`: `"Run /run-plan <plan-file> finish auto"`

   Then exit this turn.

2. **Marker exists AND fulfilled exists**: verify completed. Delete the
   attempt counter file (cleanup):
   ```bash
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/verify-pending-attempts.$TRACKING_ID"
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*       # NEW (#110)
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*    # NEW (#110)
   ```
   Proceed to sub-step 1.

3. **No marker** (standalone plan, not via /research-and-go): proceed to
   sub-step 1.

### 1. Audit phase compliance

Before declaring the plan complete, verify every phase has a clean status:

1. **Check completion indicators** — every phase must have one of: Done,
   a commit hash, ✅, `[x]`. If any phase lacks a completion indicator,
   WARN (do not hard-block):
   > Phase 3 has no completion indicator — review before closing.

2. **Scan for unresolved gaps** — check each phase's status line AND its
   corresponding section in `reports/plan-{slug}.md` for any of these
   phrases (case-insensitive): "noted as gap", "deferred", "skipped",
   "future work". If found, WARN (do not hard-block):
   > Phase 3 has unresolved gaps — review before closing.

   List all flagged phases together so the user can review in one pass.

3. If running with `auto` and warnings were emitted, log them in the
   report but continue — these are advisory, not blocking.

### 2. Close linked issue (if any)

If the plan file has YAML frontmatter with an `issue:` field (e.g.,
`issue: 42` or `issue: "#42"`):

1. **Check issue state:**
   ```bash
   gh issue view <N> --json state --jq '.state'
   ```

2. **If open:** close it with a summary comment listing key commits and
   what was accomplished:
   ```bash
   gh issue close <N> --comment "Resolved via plan execution.

   Plan: <plan-file>
   Key commits: <comma-separated list of commit hashes from all phases>
   Phases completed: <count>

   All phases passed verification. See reports/plan-{slug}.md for details."
   ```

3. **If already closed:** no action needed — log "Issue #N already closed."

4. **If no `issue:` field:** skip this step entirely.

### 3. Update plan frontmatter

Change `status: active` (or `status: in-progress`) to `status: complete`
in the plan file's YAML frontmatter. If the plan has no `status:` field,
add one: `status: complete`. Commit (mode-conditional per PR-mode rule):
```bash
# PR mode only: cd "$WORKTREE_PATH" first (cherry-pick/direct: stay on main)
git add <plan-file>
git commit -m "chore: mark plan complete — <plan-name>"
```

### 4. Update SPRINT_REPORT.md

Check if `SPRINT_REPORT.md` exists in the repo root. If it does:

1. Search for the closed issue number (from step 2) or the plan filename
   in a "Skipped" section (look for headers or list items containing
   "Skipped", "Too Complex", "Deferred", or "Punted").

2. If found, append a note to that entry:
   > Resolved via /run-plan (plan: <plan-file>)

3. If `SPRINT_REPORT.md` does not exist, or the issue/plan is not
   mentioned in a skipped section, skip this step.

### 5. Remind about stale tracking markers

After plan completion, the `fulfilled.run-plan.<id>` marker stays on disk
as the canonical completion record, but the pipeline's `requires.*`,
`step.*`, `verify-pending-attempts.*`, and `fulfilled.verify-changes.*`
markers (which are bookkeeping, not history) persist in
`.zskills/tracking/` indefinitely. Over many plan runs these accumulate
and can cause subtle drift (e.g., a test that invokes the hook's push
path from a zskills-tracked worktree may trip tracking enforcement
against a leftover `requires.*` from a prior pipeline).

Count remaining non-completion markers across all pipelines and surface
a one-line reminder. Do NOT auto-clean — this skill's job is
to run plans, not manage long-term tracking state. The user runs
`bash .claude/skills/update-zskills/scripts/clear-tracking.sh` when they're ready.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Count markers from both layouts during the Phase 2-6 transitional window:
# (1) per-pipeline subdirs (.zskills/tracking/*/…) — Option B primary, and
# (2) legacy flat basenames directly under .zskills/tracking/ — flat fallback.
MARKER_COUNT=$(ls "$MAIN_ROOT/.zskills/tracking/"*/requires.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/step.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/verify-pending-attempts.* \
                    "$MAIN_ROOT/.zskills/tracking/"*/fulfilled.verify-changes.* \
                    "$MAIN_ROOT/.zskills/tracking/"requires.* \
                    "$MAIN_ROOT/.zskills/tracking/"step.* \
                    "$MAIN_ROOT/.zskills/tracking/"verify-pending-attempts.* \
                    "$MAIN_ROOT/.zskills/tracking/"fulfilled.verify-changes.* 2>/dev/null \
                | wc -l)
if [ "$MARKER_COUNT" -ge 10 ]; then
  echo "NOTE: $MARKER_COUNT bookkeeping tracking markers on disk across completed pipelines."
  echo "      Run: bash .claude/skills/update-zskills/scripts/clear-tracking.sh   (preserves fulfilled.run-plan.* completion records)"
fi
```

Threshold `10` is a judgment call — below that the accumulation is not
yet disruptive. Adjust if it proves noisy or too quiet in practice.

## Phase 5c — Chunked finish auto transition (CRITICAL for finish auto mode)

When `finish auto` is active and Phase 5b determined another phase
is queued, Phase 5c transitions execution to the next phase via a
one-shot cron.

**Read [references/finish-mode.md](references/finish-mode.md) in full
and follow its procedure.** It covers cron scheduling, timestamp/TZ
handling, and Phase 5b gating. Do not proceed past Phase 5b without
reading this file.

## Phase 6 — Land

**If LANDING_MODE = direct**: Read [modes/direct.md](modes/direct.md) in full and follow it.

**If LANDING_MODE = delegate**: Read [modes/delegate.md](modes/delegate.md) in full and follow it.

**If LANDING_MODE = cherry-pick (default)**: Read [modes/cherry-pick.md](modes/cherry-pick.md) in full and follow it.

**If LANDING_MODE = pr**: Read [modes/pr.md](modes/pr.md) in full and follow it.

### Post-landing tracking

After successful landing (cherry-pick + tests pass), create the land step
marker and update the fulfillment file:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.land"

printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: complete\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID"
```

Remove the worktree's `.zskills-tracked` to avoid associating future agents with a dead pipeline:
```bash
rm -f "<worktree-path>/.zskills-tracked"
```

In `finish` mode, per-phase markers use the `phasestep` prefix (the hook
ignores these — they are informational only):
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
printf 'phase: %s\ncompleted: %s\n' "$PHASE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.implement"
```
After the cross-phase verification in `finish` mode completes, aggregate
with `step.*` markers:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
for stage in implement verify report land; do
  printf 'phases: all\ncompleted: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.run-plan.$TRACKING_ID.$stage"
done
```

### Post-run invariants check (mandatory — mechanical gate)

Before declaring the run complete, the orchestrator MUST invoke
`.claude/skills/run-plan/scripts/post-run-invariants.sh` to assert end-state correctness. This
catches silent failures in `land-phase.sh` (e.g., a branch delete that
was accepted but didn't take effect) that would otherwise accumulate
zombies across runs. The script is an enforced gate — NOT prose the
orchestrator might "satisfy conceptually" and skip.

Invoke it with named args, unified across modes (cherry-pick and PR use
the same `FEATURE_BRANCH` variable; direct mode passes empty for both
worktree and branch):

```bash
# FEATURE_BRANCH unified across modes — both cherry-pick and PR set this
# at worktree creation time (cherry-pick uses cp-${PLAN_SLUG}-${PHASE},
# PR uses ${BRANCH_PREFIX}${PLAN_SLUG}).
bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/post-run-invariants.sh" \
  --worktree      "$WORKTREE_PATH" \
  --branch        "$FEATURE_BRANCH" \
  --landed-status "$LANDED_STATUS" \
  --plan-slug     "$PLAN_SLUG" \
  --plan-file     "$PLAN_FILE"
```

The script asserts 7 invariants:
1. Worktree directory gone from disk
2. Worktree removed from git's worktree registry
3. Local feature branch deleted (when `--landed-status landed`)
4. Remote feature branch deleted (when `--landed-status landed`)
5. Plan report exists at `reports/plan-<slug>.md`
6. No 🟡 In Progress rows linger in the tracker
7. Local main reconcilable with origin/main (WARN-level; user may have
   legitimate unpushed local commits)

Non-zero exit from the script means one or more invariants failed. When
that happens: STOP. Do not self-reschedule the cron. Do not advance to
the next phase. Report the specific failures to the user; they need to
investigate and fix before another run.

For direct mode (no worktree, no feature branch), pass empty strings
for `--worktree` and `--branch`; the script skips those checks.

**Unified FEATURE_BRANCH convention:** at worktree creation (Phase 2),
both cherry-pick and PR modes export a single `FEATURE_BRANCH` variable
that the invariants check reads. Cherry-pick sets it to the
auto-generated `cp-${PLAN_SLUG}-${PHASE}`; PR mode sets it to
`${BRANCH_PREFIX}${PLAN_SLUG}`. Do not use different variable names per
mode — that's how invariant #3 silently skips in cherry-pick mode.

## Failure Protocol

**Read [references/failure-protocol.md](references/failure-protocol.md)**
for crash handling, cron cleanup, working-tree restoration, failure-report
template, and user-facing failure messaging. The failed-run report
template is in the same file.

## Key Rules

- **"Noted as gap" is a FAILURE, not a pass.** If the implementer skips
  a work item and the verifier writes "gaps noted" or "not a blocker" —
  that is a verification failure. Dispatch a fix agent for the missing
  items. Do not advance to Phase 4. Do not write "gaps noted" in reports.
  Past failure: Block Expansion Phase 1 skipped example model + runtime
  entry; verifier accepted both skips instead of invoking Failure Protocol.
- **Never weaken tests** — fix the code, not the test. Do not loosen
  tolerances, skip assertions, or remove test cases.
- **Honest status reporting** — if the user asks "are you stuck?", answer
  with DATA: (1) current phase and when it started, (2) agent duration and
  tool call count, (3) errors or retries. Do not say "everything is fine"
  if an agent has been running >30 minutes or retried 2+ times.
- **Plan-text drift signals.** Implementation and verification
  agents MUST emit a `PLAN-TEXT-DRIFT:` token (format above) for
  each numeric acceptance criterion that doesn't match reality.
  Phase 3.5 parses these to decide whether to auto-correct the
  plan. Token format forbids `:` and `=` inside `<field>`.

## Edge Cases

- **No progress tracker:** LLM reads plan sections + checks codebase for
  evidence of completion (files exist, tests pass, git log mentions the phase)
- **Phase fails verification:** auto mode tries one fix cycle (dispatch fix
  agent + re-verify), then stops after 2 total cycles
- **All phases complete:** report "Plan complete", delete cron if scheduled
- **Dependency not met:** stop cleanly, report which dependency. If `every`,
  the cron retries on next invocation (the dependency may be completed by then)
- **Phase "In Progress":** another agent may be working — stop, don't compete.
  Report the conflict.
- **Existing worktree for phase:** previous incomplete run — ask user
  (interactive) or try to resume from the existing worktree (auto)
- **Implementation produces no commits:** the agent worked but committed
  nothing. Report in `reports/plan-{slug}.md` as "No commits produced — investigate
  worktree." Do not attempt to cherry-pick nothing. In auto mode, invoke
  the Failure Protocol (this is an unrecoverable state for cron)
- **Plan file not found:** stop immediately, report the error
- **Phase arg doesn't match any phase:** stop, list available phases
