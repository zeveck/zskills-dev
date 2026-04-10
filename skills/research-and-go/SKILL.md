---
name: research-and-go
argument-hint: "<broad goal description>"
description: >-
  Full pipeline: decompose a broad goal into sub-plans, draft each with
  adversarial review, then execute all of them autonomously. One command,
  walk away. Usage: /research-and-go <description>
---

# /research-and-go \<description> — Plan and Execute Everything

The full autonomous pipeline in one command. Decomposes a broad goal into
focused sub-plans, drafts each with adversarial review, writes a meta-plan,
and immediately executes it — all without pausing for approval.

**Use when:** you trust the pipeline and want end-to-end execution from a
single description. For more control, use `/research-and-plan` (plan only)
followed by `/run-plan` (execute).

**Ultrathink throughout.**

## Arguments

```
/research-and-go <description>
```

- **description** (required) — the broad goal, in natural language.
  Same format as `/research-and-plan`.

Examples:
- `/research-and-go Add physical modeling support for thermal and mechanical domains`
- `/research-and-go Implement all missing block diagram tool blocks from the gap analysis`
- `/research-and-go Close the runtime deployment parity gap`

## Step 0 — Tracking Setup

Before anything else, check whether another pipeline is already in progress.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.claude/tracking"
```

**Check for existing pipeline:** If `$MAIN_ROOT/.claude/tracking/pipeline.active`
exists, STOP. Read the file and report its contents — another pipeline is already
in progress. Do not proceed unless this is a deliberate re-run (see Re-run
Handling below).

**Create the sentinel:**

```bash
printf 'skill=research-and-go\ngoal=%s\nstartedAt=%s\n' "$DESCRIPTION" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/pipeline.active"
```

Where `$DESCRIPTION` is the broad goal passed to this command.

**Lock down the final cross-branch verification requirement immediately
(Change 4 mechanical enforcement).** The pipeline will end with a
top-level `/verify-changes branch` invocation that runs as a cron-fired
turn after the meta-plan execution completes. By creating the requirement
marker NOW (before any implementation), the hook will block any commit
on main until this final verification has been fulfilled. The orchestrator
cannot skip the final cross-branch check.

```bash
printf 'skill=verify-changes\nscope=branch\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.verify-changes.final"
```

### Re-run Handling

If `pipeline.active` already exists and this is a deliberate re-run of the same
goal:

1. Read the existing `pipeline.active` to confirm the goal matches.
2. Check which `requires.*` files already exist in `$MAIN_ROOT/.claude/tracking/`.
3. For each existing requirement, check if a corresponding `completed.*` file
   exists. Only create new requirement files for unfulfilled requirements.
4. Overwrite `pipeline.active` with a fresh timestamp.

## Step 1 — Decompose and Draft

Invoke `/research-and-plan` with `auto` and the full description:

`/research-and-plan auto <description>`

This:

1. Dispatches research agents to survey the domain
2. Identifies sub-problems and dependencies
3. Sizes scope for each sub-plan
4. **Skips the user confirmation checkpoint** — `auto` flag.
5. Drafts each sub-plan via dispatched `/draft-plan` agents
   (each gets full adversarial review in its own context)
6. Writes the meta-plan with pure implementation phases

The meta-plan file path comes back from `/research-and-plan`.

## Step 1b — Lock Down Requirements

After `/research-and-plan` returns and before execution begins, create tracking
requirement files for every sub-plan and the meta-plan itself. These files let
any observer (or a re-run) know exactly what the pipeline expects to accomplish.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
```

For each sub-plan index `i` (from 1 to N, where N is the number of sub-plans
produced by `/research-and-plan`):

```bash
for i in 1 2 ... N; do
  printf 'skill=draft-plan\nindex=%d\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$i" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.draft-plan.$i"
  printf 'skill=run-plan\nindex=%d\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$i" "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.run-plan.$i"
done
```

Also create a requirement for the meta-plan execution itself:

```bash
printf 'skill=run-plan\nid=meta\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$(date -Iseconds)" > "$MAIN_ROOT/.claude/tracking/requires.run-plan.meta"
```

Replace `1 2 ... N` with the actual sub-plan indices. The `draft-plan`
requirements track the planning phase; the `run-plan` requirements track
execution.

**Pass tracking IDs to child skills:** When dispatching `/run-plan` for each
sub-plan, include the tracking index so child skills can mark their
corresponding requirement as completed. For example, include
`tracking-index=3` in the dispatch prompt for sub-plan 3.

## Step 2 — Hand off to chunked /run-plan execution

**Do NOT invoke `/run-plan` inline in this turn.** Long-running pipelines
that all run in one turn cause late-phase fatigue (the original failure
mode). Instead, schedule a one-shot cron to fire `/run-plan finish auto`
in a fresh turn ~1 minute from now. The cron-fired turn runs at top level,
processes the meta-plan with chunked execution (each phase as its own
cron-fired turn), and the whole pipeline unfolds as a sequence of fresh
top-level turns.

```bash
# Compute a target minute that is NOT :00 or :30 (to avoid scheduler jitter)
NOW_MIN=$(date +%M)
NOW_HOUR=$(date +%H)
NOW_DAY=$(date +%d)
NOW_MONTH=$(date +%m)
TARGET_MIN=$(( (10#$NOW_MIN + 1) % 60 ))
# If we landed on :00 or :30, bump by 1 more
if [ "$TARGET_MIN" -eq 0 ] || [ "$TARGET_MIN" -eq 30 ]; then
  TARGET_MIN=$(( TARGET_MIN + 1 ))
fi
TARGET_HOUR=$NOW_HOUR
if [ "$TARGET_MIN" -lt "$NOW_MIN" ]; then
  TARGET_HOUR=$(( (10#$NOW_HOUR + 1) % 24 ))
fi
```

Then call `CronCreate`:

- `cron`: `"$TARGET_MIN $TARGET_HOUR $NOW_DAY $NOW_MONTH *"`
- `recurring`: false
- `prompt`: `"Run /run-plan <meta-plan-path> finish auto"`

After scheduling the cron, output to the user:

> Pipeline starting. Meta-plan: `plans/<META_PLAN>.md` with N sub-plans.
>
> The first phase will fire in ~1-2 minutes as a fresh turn. Each subsequent
> phase will fire similarly. The whole pipeline runs as a sequence of fresh
> cron-fired turns at the top level — no late-phase fatigue, full Agent tool
> available at every step, full visibility for you.
>
> To stop the pipeline at any point: `/run-plan stop`
> To check progress: `/run-plan plans/<META_PLAN>.md status`
> To clean up tracking after completion: `! bash scripts/clear-tracking.sh`

Then **exit this turn**. Do NOT wait for /run-plan. The cron handles the
rest.

## Step 3 — Final cross-branch verification (scheduled by /run-plan, not here)

The `requires.verify-changes.final` marker created in Step 0 ensures that
no commit on main can be cherry-picked until a top-level `/verify-changes
branch` has been run and produced its `fulfilled.verify-changes.final`
marker.

When `/run-plan` reaches the end of the meta-plan (last phase of last
sub-plan landed), instead of exiting, it schedules ONE MORE cron whose
prompt is `"Run /verify-changes branch"`. This cron fires at top-level,
where `/verify-changes` has full Agent tool access and can dispatch its
diff/coverage/manual sub-agents for proper multi-agent cross-branch
verification. When `/verify-changes` completes, it creates the
`fulfilled.verify-changes.final` marker, the hook unblocks commits, and
the pipeline is officially done.

The user sees the final-verify report as the last turn in the chain. That
report is the pipeline's cap — read it carefully for any cross-sub-plan
inconsistencies the per-sub-plan verifications missed.

**Note for /run-plan implementers:** When /run-plan completes the LAST
phase of the LAST sub-plan in a meta-plan that's part of a
research-and-go pipeline (detect this by the presence of
`requires.verify-changes.final`), schedule the final-verify cron BEFORE
exiting the chunked transition. Use:
- `cron`: target minute non-:00/:30, ~1 minute from now
- `recurring`: false
- `prompt`: `"Run /verify-changes branch"`

### Pipeline Cleanup

After the final cross-branch verification has fulfilled its requirement,
the user can clean up tracking with:

```
! bash scripts/clear-tracking.sh
```

The pipeline does NOT auto-clean. The user does it manually so they have
a chance to inspect the tracking state before discarding it.

If the pipeline failed at any point, tracking is preserved for inspection
and re-run. See Step 0 Re-run Handling for the resume protocol.

## Key Rules

- **No confirmation checkpoints.** The user said `go` — that's blanket
  approval for decomposition, planning, and execution. Do not pause
  between steps.
- **Failure still stops.** If `/run-plan` hits the Failure Protocol
  (cherry-pick conflict, test failures after landing, verification
  fails after 2 cycles), it stops and reports. `go` means autonomous,
  not reckless.
- **Sub-plan staleness refresh applies.** If a later sub-plan depends
  on an earlier one, `/run-plan` auto-refreshes it via `/draft-plan`
  before execution (the staleness check in Phase 1 step 6).
- **This is the top of the pipeline.** The execution chain:
  `/research-and-go` → `/research-and-plan` → `/draft-plan` (×N) →
  `/run-plan` (meta) → `/run-plan` (×N sub-plans) → `/verify-changes`
  (×N) → `/commit` (×N landings).
