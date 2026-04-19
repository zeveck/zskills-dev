# /run-plan — Finish-Auto Chunked Execution

Chunked per-phase execution for finish auto mode: each phase runs as a fresh cron-fired top-level turn with idempotent re-entry.
## Phase 5c — Chunked finish auto transition (CRITICAL for finish auto mode)

**This section applies when running `/run-plan <plan> finish auto`.**

In chunked finish auto mode, each plan phase runs as a separate top-level
cron-fired turn. The current turn does NOT loop back to process the next
phase — instead, it lands the current phase, schedules a one-shot cron for
the next phase (or the next meta-plan phase, or the final cross-branch
verification, depending on context), and exits cleanly.

### Why chunked execution

The original failure mode was: a single long-running session built up
late-phase fatigue and rationalized skipping verification on the last few
phases. Chunked execution breaks the run into a sequence of fresh
top-level turns, each handling exactly one plan phase. Each fresh turn
re-reads the plan, the tracking state, and its own instructions. There
is no momentum to skip steps because each turn starts clean.

A secondary benefit: cron-fired turns run at top level (in the user's
main session, with full `Agent`/`Task` tool access). This means
implementation, verification, and reporting subagent dispatches all work
correctly. Sub-sub-agent dispatch is not needed because there is no
nesting — every cron fire is a fresh top-level turn.

### Idempotent re-entry (every cron-fired turn does this first)

Cross-reference: Step 0 in Phase 1 preflight. At the very start of every
`/run-plan` invocation in `finish auto` mode, read the plan tracker and
check the next-target phase. If it's already marked Done OR In Progress,
**exit cleanly** with a "no work to do" message. This handles two cases:

1. A stale cron from a previous run fires after the user manually
   re-invoked the next phase. The cron sees the work is already done
   and exits without duplication.
2. A previous turn already started this phase (e.g., is mid-cherry-pick).
   The new turn defers and exits.

Output for the no-work-to-do case:
> /run-plan plans/X.md: phase N is already Done/In Progress. Skipping
> this cron fire (likely a stale cron). The pipeline is still proceeding
> via its actual current phase.

### When this turn schedules the next cron

After Phase 6 (land) succeeds for the current phase AND
`scripts/post-run-invariants.sh` passes:

> **`post-run-invariants.sh` ordering**: Phase 5c's next-phase cron
> schedule runs AFTER `post-run-invariants.sh` passes. If invariants
> fail, do NOT schedule the next cron; invoke Failure Protocol.

1. **NEXT incomplete phase exists in this plan**: schedule a one-shot cron
   (`recurring: false`) for `/run-plan <plan-file> finish auto` ~5 min
   from now. The next cron-fired turn will pick up the next phase. Then
   exit this turn.

2. **This plan is a sub-plan delegate** (detected via `tracking-index=N`
   arg from research-and-go Step 1b — see `skills/research-and-go/SKILL.md:135`):
   after the last phase of this sub-plan lands, recover the meta-plan path
   from `requires.run-plan.N` marker content (or
   `pipeline.research-and-go.*` sentinel — see Step 1b). Schedule a
   one-shot cron for `/run-plan <META_PLAN_PATH> finish auto` ~5 min
   from now. The next cron-fired turn will resume the meta-plan from its
   next incomplete delegate phase. Then exit.

3. **All phases done (meta or standalone)**: do NOT schedule a next-phase
   cron. Phase 5b has already run (or will run on the next `/run-plan`
   invocation/re-entry — see Phase 1 step 3 amendment). Exit cleanly. The
   final-verify gate lives in Phase 5b's first sub-step (see Phase 5b
   0b. Final-verify gate); Phase 5c does not handle final-verify directly.

### PR-mode branching for next-phase cron

Do NOT poll `gh pr view --json state` inside the cron turn. Instead,
Phase 5c reads the just-written `.landed` status file (written at landing
time):

- `status: landed` → schedule next-phase cron, exit.
- `status: pr-ready` or `pr-ci-failing` → schedule a SHORT re-entry cron
  (~5 min) whose prompt re-fires `/run-plan <plan> finish auto`. Step 0's
  idempotent check will see the current phase is still In Progress and
  re-attempt the PR-state poll via Phase 6.
- `status: conflict` or `pr-failed` → invoke Failure Protocol. Do not
  schedule next cron.
- In cherry-pick / direct mode, the land event is synchronous (`.landed`
  written immediately) and next-phase cron schedules directly.

### User Verify items in chunked mode

In chunked mode, landing happens per-phase. If the just-landed phase has
User Verify items, schedule the next-phase cron AND output the User Verify
items in this turn's completion message. Per-phase landing IS the chunked
model — do NOT hold landing until all phases complete.

### How to schedule the next cron

Compute the cron expression via `scripts/compute-cron-fire.sh`. The
helper handles +5 default margin (scheduler-jitter slack), :00/:30
avoidance (API busy marks), and all minute/hour/day/month/year
rollovers.

```bash
# Default behavior: +5 minutes, avoid :00/:30 marks.
NEXT_CRON=$(bash scripts/compute-cron-fire.sh)
```

**TZ note:** the helper reads `date +%s` in SYSTEM-local TZ, which is
what CronCreate also expects. Do NOT override with
`TZ=America/New_York date` — that encodes ET into the expression while
CronCreate reads system-local, producing a cron pinned to an
already-passed slot (next fire ~365 days out). The user-facing message
uses ET for readability; the cron expression itself MUST stay
system-local.

**Why +5 (not +1):** one-shot crons pin day-of-month AND month. If
scheduler jitter (sub-minute clock drift, TZ-conversion rounding, tick
skew) makes the fire window appear "already passed" at evaluation
time, the next matching slot is day-of-month+month NEXT YEAR — the
cron sits in CronList forever but won't fire this session. 1-minute
margin is borderline; 5 minutes is comfortable slack. Observed in the
wild: a chunked finish-auto pipeline's 5th consecutive +1 cron missed
its window and stalled the entire run.

**Why day/month rollover matters:** inlined versions of this math
previously got the rollover wrong. At 23:58 the naive
`NOW_MIN + 5 → TARGET_HOUR = (NOW_HOUR + 1) % 24 = 0` produced a cron
pinned to TODAY at 00:03 — already earlier today. The helper uses
`date -d @<epoch + N*60>` which gets all rollovers right.

Then call `CronCreate`:
- `cron`: `"$NEXT_CRON"`
- `recurring`: false
- `prompt`: the next-step prompt — typically `"Run /run-plan <plan-file> finish auto"`, or `"Run /run-plan <meta-plan-path> finish auto"`, or `"Run /verify-changes branch tracking-id=$TRACKING_ID"`

After scheduling, output the chunking message:
> Phase <N> of `<plan>` complete (commit `<hash>`).
> Phase <N+1> will fire automatically in ~5 minutes (cron `<job-id>`).
> To stop the pipeline: `/run-plan stop`
> To check status: `/run-plan <plan> status`

Then **exit this turn**. Do NOT do any other work. Do NOT loop back to
process the next phase inline. The cron handles it.

### Cron-scheduling rule (avoid confusion)

**Only top-level orchestrators (this `/run-plan` running as a cron-fired
top-level turn) call `CronCreate`.** Sub-agents (the implementer in the
worktree, the verifier subagent dispatched by Phase 3) do NOT schedule
crons. They do their work synchronously and return control to this top-
level orchestrator. This ensures at most one pending chunking cron per
pipeline at any time.

### Single-phase mode (no chunking)

When invoked WITHOUT `finish auto` (e.g., `/run-plan plans/X.md` or
`/run-plan plans/X.md 4b`), do NOT chunk. Run the single specified phase
to completion in this turn, then exit normally. Chunking is exclusively
for `finish auto` mode.

