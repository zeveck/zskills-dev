---
name: run-plan
disable-model-invocation: false
argument-hint: "<plan-file> [phase|finish|status] [auto] [pr|direct] [every SCHEDULE] [now] | stop | next"
description: >-
  Execute the next phase of a plan: parse status, dispatch implementation
  in a worktree, verify via a separate agent, update progress, write the
  plan report (`$ZSKILLS_REPORTS_DIR/plan-{slug}.md`), and optionally
  auto-land to main. Self-schedules via cron; use `next` to check, `stop`
  to cancel.
metadata:
  version: "2026.05.31+c74b30"
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
  Without `auto`: pauses BETWEEN phases to show results and ask
  "continue to next phase?" With `auto` (or the `finish auto` composite
  alias): each phase runs as its own cron-fired top-level turn (~5 min
  between phases via one-shot crons scheduled by Phase 5c). The first
  phase runs immediately; each subsequent phase is scheduled after the
  prior phase lands. Preserves fresh context per phase — no late-phase
  fatigue. Each phase still gets full verification, testing, and all
  safety rails. If any phase fails verification or hits a conflict,
  stops there.
  **`finish` and `every` are mutually exclusive.** `finish auto` schedules
  its own ~5-min one-shot crons internally. `every N` schedules a recurring
  cron at user-set cadence. Combining them would produce two overlapping
  cron schedules. Use one or the other.
- **auto** (optional) — run autonomously: skip scope-confirmation /
  approval prompts and human-review pauses (between-phase pause, drift
  findings, staleness check, verifier-fail review) so the skill can run
  without an attended user, AND pass `--auto` to per-phase `/land-pr`
  dispatches (auto-merge the resulting PR). The `finish auto` composite
  is an alias that hoists `auto` (backward-compat per D2-RP).
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
# Resolve repo root before any config read. $PROJECT_ROOT is never exported
# into a SKILL.md fence (it is only set inside post-run-invariants.sh, a
# separate process), so anchor it on $CLAUDE_PROJECT_DIR -- the established
# peer pattern used elsewhere in this skill (#791).
PROJECT_ROOT="${PROJECT_ROOT:-$CLAUDE_PROJECT_DIR}"
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

**Finish-mode resolution.** `$FINISH_MODE` is set deterministically from
args (NOT orchestrator-tracked) so downstream conditionals (cherry-pick
worktree gating, PR title construction, etc.) see a single canonical
value. Values are exactly `"finish"`, `"finish-auto"`, or empty —
nothing else is valid. Any downstream check that reads `$FINISH_MODE`
must match against these three states.

```bash
# Detect finish mode (canonical values: "finish", "finish-auto", "")
FINISH_MODE=""
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[fF][iI][nN][iI][sS][hH]($|[[:space:]]) ]]; then
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
    FINISH_MODE="finish-auto"
  else
    FINISH_MODE="finish"
  fi
fi

# AUTO_FLAG: set by standalone `auto` (regardless of finish), OR by the
# `finish auto` composite (backward-compatible alias per D2-RP).
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi

# Backward-compatible composite: `finish auto` implies AUTO_FLAG.
# The post-detection hoist preserves the load-bearing user workflow
# `/run-plan plan.md finish auto every 4h`.
if [ "$FINISH_MODE" = "finish-auto" ]; then
  AUTO_FLAG=1
fi

# AUTO_ARG: the suffix string to thread into every child-skill dispatch
# that recognizes positional `auto` (e.g. /refine-plan, /draft-plan,
# /draft-tests per #581 / PR #642). Empty when AUTO_FLAG=0 so children
# stay in non-auto behavior. Closure-incomplete #648 sites used this.
AUTO_ARG=""
if [ "$AUTO_FLAG" = "1" ]; then
  AUTO_ARG=" auto"
fi
```

**Validation:**

```bash
# direct + main_protected -> error
PROJECT_ROOT="${PROJECT_ROOT:-$CLAUDE_PROJECT_DIR}"
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
PROJECT_ROOT="${PROJECT_ROOT:-$CLAUDE_PROJECT_DIR}"
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
PROJECT_ROOT="${PROJECT_ROOT:-$CLAUDE_PROJECT_DIR}"
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
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
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

## Subcommands: status, now, next, stop

Select the subcommand based on `$ARGUMENTS`, then **read the
corresponding file in full and follow its procedure end-to-end**.
Do not proceed until you have read the file. Each subcommand exits
before Phase 1.

| Subcommand | File |
|------------|------|
| `status`   | [subcommands/stop-next-status.md](subcommands/stop-next-status.md) |
| `now` (standalone) | [subcommands/stop-next-status.md](subcommands/stop-next-status.md) |
| `next`     | [subcommands/stop-next-status.md](subcommands/stop-next-status.md) |
| `stop`     | [subcommands/stop-next-status.md](subcommands/stop-next-status.md) |

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
   this `now` is for the CRON's invocation, not the current invocation.

   **Assemble the prompt from `$AUTO_FLAG` state, not from literal
   `$ARGUMENTS` substrings.** Cron-fired `every`-mode runs MUST advance
   between phases without human interaction, so include `auto`
   unconditionally for new `every` crons (auto = autonomous = skip
   between-phase pause + auto-merge):
   ```bash
   CRON_TOKENS=""
   # `auto` is mandatory for `every`-mode crons (between-phase advance
   # must be non-interactive). Default-on regardless of $AUTO_FLAG.
   CRON_TOKENS="$CRON_TOKENS auto"
   CRON_PROMPT="Run /run-plan $PLAN_FILE$CRON_TOKENS every $SCHEDULE now"
   ```
   Default new-cron shape: `Run /run-plan <plan-file> auto every <schedule> now`.
   Note: the phase number is intentionally omitted so the cron auto-advances.

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the constructed command from step 3

5. **Confirm** with wall-clock time. **Always show times in the configured
   timezone** — use `TZ="${TIMEZONE:-UTC}" date` for conversion, not the
   system timezone (which may differ):

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
# Pre-worktree bootstrap: anchor on $CLAUDE_PROJECT_DIR (orchestrator session
# root) — WORKTREE_PATH is not yet in scope at the read-authority block.
MAIN_ROOT="$CLAUDE_PROJECT_DIR"
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
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   # MAIN_ROOT is already in scope from the "Read authority" block earlier
   # in this section (line ~393); reuse it here.
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
   if compgen -G "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed.*" >/dev/null 2>&1; then
     # CronList → check if a "Run /run-plan <plan-file> finish auto" cron
     # already exists (a stale fire from before the failed Delete may have
     # raced ahead of us). The literal `finish auto` composite alias is
     # preserved indefinitely (D2-RP load-bearing user workflow): on
     # /run-plan re-entry, the parser sets FINISH_MODE=finish-auto and
     # hoists AUTO_FLAG=1, so the cron-fired turn runs autonomously and
     # lands with --auto.
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
      if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
        . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
      else
        . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
      fi
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
      PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
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
      if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
        . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
      else
        . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
      fi
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
      PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
      rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
      rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
      ```
      (Harmless on first phase — rm of missing files is a no-op.)

   Stale crons are harmless — duplicate fires exit cleanly via this
   check. Re-entry routes to Phase 5b which owns verify-pending state
   and self-rescheduling.

**Plan-claim acquire (W2a.1, A11 / AC2a.7).** Acquire a single-host
atomic claim on this plan BEFORE any mode-detection branch (so the claim
is reachable from worktree / PR / cherry-pick / direct / delegate paths).
On race-lost (exit 10) this fence terminates cleanly; the orchestrator
reports "declined" and exits the turn — a second pipeline already owns
the plan and our session must not double-fire `/run-plan` for it.

`claim-plan.sh` is ownership-aware (self-re-entry returns 0), so a chunked
`finish auto` re-fire re-acquiring its OWN plan claim with the stable
`run-plan.$TRACKING_ID` pipeline_id succeeds — exit 10 here therefore means
ONLY a truly-foreign pipeline holds the plan, which is exactly when
"declined" is the correct verdict (D8 / #803).

### Self-re-entry contract (twins: claim-plan.sh / claim-issue.sh)

Both twin primitives share one ownership-aware self-re-entry decision,
implemented by the helper `skills/create-worktree/scripts/claim-self-reentry.sh`
(invoked as a bash subprocess on each twin's already-exists branch — NEVER
sourced, since its exit codes would terminate a sourcing caller). The
exit-code contract is: **acquire** — `0` = fresh-OR-self (the existing claim
is the caller's own pipeline_id, or there was no claim and we just took it →
proceed), `10` = foreign-OR-absent/malformed (another pipeline holds it, or
claim.json is missing/truncated → never steal), `11` = filesystem
infrastructure failure, `2` = usage error; **release** — `12` = ownership
mismatch (the claim is held by a different pipeline_id; release refuses).
There is NO TTL — a claim is released ONLY by an explicit `release` call, so
a re-entering self always sees its own claim and proceeds (`0`), and a
foreign holder is honored until that holder explicitly releases.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
# Resolve dispatch_mode for the claim record (issue #874 — sibling to
# #858). The chip's lock condition reads plan.claim.dispatch_mode, which
# outlives the /work-on-plans wrapper that spawned this /run-plan. Map
# the canonical $FINISH_MODE ("finish"|"finish-auto"|"") to the
# claim-side enum (phase|finish|inherit).
DISPATCH_MODE_FOR_CLAIM="phase"
if [ "$FINISH_MODE" = "finish" ] || [ "$FINISH_MODE" = "finish-auto" ]; then
  DISPATCH_MODE_FOR_CLAIM="finish"
fi
set +e
bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
  acquire "$PLAN_SLUG" --pipeline-id "$PIPELINE_ID" \
  --dispatch-mode "$DISPATCH_MODE_FOR_CLAIM"
rc=$?
set -e
case "$rc" in
  0) : ;;
  10) echo "Plan $PLAN_SLUG is in-flight by another pipeline; this invocation declined." >&2; exit 0 ;;
  11) echo "claim-plan.sh acquire infrastructure failure"; exit 1 ;;   # Failure Protocol
  2)  echo "claim-plan.sh acquire usage error"; exit 2 ;;
  *)  echo "claim-plan.sh acquire unexpected rc=$rc"; exit 1 ;;
esac
```

**Issue-claim acquire (W3.1/W3.2/W3.5, #803 execution-window protection).**
If the plan's frontmatter carries one or more `issue: N` fields, claim each
linked `issue-<N>` for the plan's FULL lifetime — held across idle gaps
between chunked fires (filesystem + no-TTL + self-re-entry make this
automatic) and released ONLY at the plan's terminal release points
(execute-phase.md terminal merge, the already-complete no-op, and the
operator-stop sweep — NEVER per-phase). The issue claim uses run-plan's OWN
`$PIPELINE_ID` (same as the plan claim) and `--sprint-id "$PIPELINE_ID"`.

This arm is **DELIBERATELY different from the plan-claim decline arm above**:
issue-foreign-at-start is **WARN-and-PROCEED**, never abort. #739 removed
auto-expiry, so a possibly-stale issue claim must not block a deliberately-run
plan — the plan owns the plan; the issue contention is a softer operator
signal. On rc=10 we log loudly and CONTINUE, and we NEVER release the
legitimately-won plan claim (no plan-claim leak).

Parse the bare-integer issue number(s) from `$PLAN_FILE_FOR_READ`'s
frontmatter (the PR-mode-worktree-aware read authority — NOT bare
`$PLAN_FILE`). Strip `#` and surrounding quotes to a bare positive integer
(`claim-issue.sh validate_issue_number` rejects non-numeric input with
exit 2), aligning with the Close-linked-issue parser's tolerance for
`issue: 42` and `issue: "#42"`.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# Parse issue:N field(s) from the plan frontmatter (the leading `---`
# delimited YAML block only), normalized to bare positive integers.
# Tolerates `issue: 42`, `issue: "#42"`, `issue: '#42'`. Multiple
# `issue:` lines → multiple claims.
ISSUE_NUMS=()
while IFS= read -r raw; do
  # strip surrounding quotes and a leading '#', keep only digits
  n=$(printf '%s' "$raw" | tr -d '"'\''#[:space:]')
  case "$n" in
    ''|*[!0-9]*) continue ;;   # skip non-numeric (defensive)
  esac
  [ "$n" -gt 0 ] 2>/dev/null && ISSUE_NUMS+=("$n")
done < <(awk '
  NR==1 && $0 != "---" { exit }            # no frontmatter → nothing to do
  NR==1 { infm=1; next }
  infm && $0 == "---" { exit }             # end of frontmatter block
  infm && /^[[:space:]]*issue:[[:space:]]*/ {
    sub(/^[[:space:]]*issue:[[:space:]]*/, "", $0); print $0
  }
' "$PLAN_FILE_FOR_READ" 2>/dev/null)

for N in "${ISSUE_NUMS[@]}"; do
  set +e
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" \
    acquire "$N" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"
  irc=$?
  set -e
  case "$irc" in
    0)  : ;;   # acquired-fresh OR self-re-entry — proceed, issue claim held
    10) echo "issue #$N is claimed by another pipeline; proceeding with plan execution, issue claim NOT held" >&2 ;;  # WARN-and-PROCEED (D9) — do NOT abort, do NOT release the plan claim
    11) echo "claim-issue.sh acquire infrastructure failure for issue #$N"; exit 1 ;;   # Failure Protocol
    2)  echo "claim-issue.sh acquire usage error for issue #$N (un-stripped #N / empty PIPELINE_ID — internal bug)"; exit 2 ;;
    *)  echo "claim-issue.sh acquire unexpected rc=$irc for issue #$N"; exit 1 ;;
  esac
done
```

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
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   for wt_line in $(git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //'); do
     if [ -f "$wt_line/.landed" ] && grep -q 'status: landed' "$wt_line/.landed"; then
       echo "Cleaning up landed worktree: $wt_line"
       bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/land-phase.sh" "$wt_line"
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
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# In a plan phase that needs an open-PR conflict gate. The orchestrator
# already tracks $RUN_PLAN_PR_NUMBER (the pipeline's own PR) — pass it via
# --exclude-pr so the gate self-filters.
if ! bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/pr-preflight.sh" \
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
     dependency was implemented. Want me to refresh it with `/refine-plan`?"
   - With `auto`: dispatch `/refine-plan <plan-file>$AUTO_ARG` on the plan
     file to update it (the trailing `$AUTO_ARG` propagates auto so
     /refine-plan's own AUTO_FLAG fires and it dispatches /land-pr per
     #648). After the refresh, re-read the plan and continue.
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
   - **Without `auto`:**
     present findings:
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
   - **With `auto`:** if
     any bullet has drift >20%, dispatch
     `/refine-plan <plan-file>$AUTO_ARG` (plan-level issue, not per-band;
     the trailing `$AUTO_ARG` propagates auto so /refine-plan dispatches
     /land-pr per #648); after refresh, re-read and continue. If all
     drifts are ≤20%, log findings to the phase report and proceed —
     Phase 3.5 will auto-correct post-hoc within the ≤20% band.

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
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   # Re-derive BRANCH_PREFIX and PLAN_SLUG at fence-top (R-5-1):
   # both were set in earlier disjoint fences (BRANCH_PREFIX@178-185,
   # PLAN_SLUG@382) and do NOT survive cross-fence per the
   # "Resolve config-derived vars at fence-top" convention
   # (modes/execute-phase.md:425).
   # Needed below for the requires.land-pr.<id> marker's branch: field.
   BRANCH_PREFIX="feat/"
   if [ -f "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" ]; then
     CONFIG_CONTENT=$(cat "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json")
     # ([^"]*) allows empty string match -- empty prefix means no prefix
     if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
       BRANCH_PREFIX="${BASH_REMATCH[1]}"
     fi
   fi
   PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   # PR mode: bookkeeping commits inside the worktree on the feature branch
   # (PR-mode bookkeeping rule). Pre-worktree fences (Phase 1 step 8 runs
   # before Phase 2 worktree creation) anchor on $PR_WORKTREE_PATH if PR-mode
   # resume detected the worktree above; otherwise on $CLAUDE_PROJECT_DIR.
   BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"
   if [ "$LANDING_MODE" = "pr" ] && [ -n "$PR_WORKTREE_PATH" ] && [ -d "$PR_WORKTREE_PATH" ]; then
     BOOKKEEPING_ROOT="$PR_WORKTREE_PATH"
   fi
   ZSKILLS_PATHS_ROOT="$BOOKKEEPING_ROOT" \
     if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
       . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
     else
       source "$BOOKKEEPING_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
     fi
   MAIN_ROOT="$BOOKKEEPING_ROOT"
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
   [ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
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

   # PR-mode only: lock down landing requirement at skill entry. Closes the
   # Phase-6-skip hole observed in PR #211 (chunked finish-auto exited after
   # Phase 5b's frontmatter flip without dispatching /land-pr in Phase 6 —
   # PR sat open and unmerged). The parent-writes-requires convention follows
   # the existing requires.verify-changes write above and the 4 other
   # writers documented in plans/REQUIRES_LAND_PR.md. The matching
   # fulfilled.land-pr.<id> is written by /land-pr when row 6 of its
   # .landed status-mapping table holds (MERGE_REQUESTED=true AND
   # PR_STATE=MERGED AND CI_STATUS in {pass, none, skipped}). Idempotent:
   # chunked finish-auto invokes /run-plan once per phase, overwrite is fine
   # (same content each invocation).
   if [ "$LANDING_MODE" = "pr" ]; then
     BRANCH_NAME_FOR_MARKER="${BRANCH_PREFIX}${PLAN_SLUG}"
     printf 'skill: land-pr\nparent: run-plan\nid: %s\nbranch: %s\ndate: %s\n' \
       "$TRACKING_ID" "$BRANCH_NAME_FOR_MARKER" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
       > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$TRACKING_ID"
   fi
   # Phase tracking (UX): update dashboard chip's current_phase. `|| true` —
   # phase-tracking is UX-not-correctness; failure must not abort the pipeline.
   bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
     set-phase "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" --current-phase "Phase $PHASE" || true
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
   - Without `auto`: display the phase summary (name, status,
     dependencies, work items, UI classification) and **wait for user
     approval**
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

## Phases 2-6 — Execute Phase

After Phase 1 parsing completes, **read
[modes/execute-phase.md](modes/execute-phase.md) in full and follow its
procedure end-to-end**. Do not proceed until you have read the file.

It covers:
- Phase 2 — Implement (worktree/delegate/direct/PR mode dispatch)
- Phase 3 — Verify (separate agent, failure protocol, drift signals)
- Phase 3.5 — Plan-text drift auto-correction
- Phase 4 — Update Progress Tracking
- Phase 5 — Write Report
- Phase 5b — Plan Completion
- Phase 5c — Chunked finish auto transition
- Phase 6 — Land (dispatches to modes/cherry-pick.md, modes/pr.md, modes/direct.md, or modes/delegate.md)

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
  nothing. Report in `$ZSKILLS_REPORTS_DIR/plan-{slug}.md` as "No commits produced — investigate
  worktree." Do not attempt to cherry-pick nothing. In auto mode, invoke
  the Failure Protocol (this is an unrecoverable state for cron)
- **Plan file not found:** stop immediately, report the error
- **Phase arg doesn't match any phase:** stop, list available phases
