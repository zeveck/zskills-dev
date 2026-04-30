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
`.claude/skills/run-plan/scripts/post-run-invariants.sh` passes:

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

### How to schedule the next cron (Design 2a — single persistent recurring cron)

**Primary path: ensure a recurring `*/1 * * * *` cron exists for this
pipeline.** Do NOT create a fresh one-shot per phase — the recurring
cron fires every minute at REPL-idle windows, and Phase 1 Step 0's
idempotent re-entry check handles redundant fires as cheap no-ops.

```bash
# Call CronList. If any existing job's prompt matches
# "Run /run-plan <plan-file> finish auto" (same prompt as what we'd
# schedule), skip creation — the cron from an earlier phase is still
# alive and will fire the next phase.
# Otherwise call CronCreate with:
#   cron: "*/1 * * * *"
#   recurring: true
#   prompt: "Run /run-plan <plan-file> finish auto"
```

**Cron terminates when the plan completes.** Phase 1 Step 0 Case 1
(frontmatter `status: complete`) explicitly deletes this cron — see
the SKILL.md main file's Phase 1 Step 0 block. That's the only
mechanism that removes it; if Case 1 fails to fire (e.g., plan
frontmatter never gets flipped), the cron keeps firing forever. The
Failure Protocol also deletes /run-plan crons as its first act, so
failure paths are also covered.

**Why recurring instead of one-shot (Design 2a).** One-shot crons pin
day-of-month and month. If scheduler jitter or an active conversation
blocks the single fire window, the cron's next matching slot is a year
later — it effectively evaporates. This is the RESTRUCTURE_RUN_PLAN
2026-04-19 Phase 5 fizzle bug. Recurring `*/1` has no pinning and no
single-window fragility; missed fires retry a minute later until an
idle window catches them.

**Why `*/1`, not `*/5`.** The original chunking design was 1 minute;
it was bumped to 5 only as jitter insurance for one-shots. Recurring
crons don't have that jitter concern, so we can revert. Each fire's
no-op cost is a few file reads and <5 seconds of work, so firing every
minute during a 10-minute phase = ~10 no-op fires = ~50 seconds of
harmless ticking.

**Preserving agent "breathing".** Fresh-top-level-turn isolation (which
is what the chunking design actually buys — see Phase 5c's "Why chunked
execution" block) is preserved regardless of gap length. Wall-clock gap
between phase completion and the next cron fire is typically 0-60s with
`*/1`; agent quality is unaffected because each turn starts clean.

**TZ note:** CronCreate reads system-local TZ. `*/1 * * * *` has no TZ
dependency (matches every minute regardless). For human-readable
messages, use `TZ=America/New_York date` — but the cron expression
itself is TZ-agnostic.

**Special case: Phase 5b final-verify gate.** Phase 5b Case 1 (marker
exists AND fulfilled missing) has a separate backoff cron — that's a
distinct concern (waiting on external verify-changes) and keeps using
`.claude/skills/run-plan/scripts/compute-cron-fire.sh` one-shots with explicit attempt-counter
exponential backoff. Leave Phase 5b's Case 1 scheduling as-is.

#### Adaptive backoff for clean defers (Issue #110)

When a phase is in flight (Step 0 Case 3 — "next-target phase already
🟡 In Progress"), the recurring `*/1` cron continues firing every
minute. Without backoff, a 30-min phase produces ~30 visible defer
turns; a longer pause produces proportionally more. Mode A (Issue #110)
adds a per-phase counter `in-progress-defers.<phase>` and steps the
cron's cadence down at boundary fires `C+1 ∈ {1, 10, 16, 26}`:

| C+1 (counter after fire) | New cadence | Cumulative wall time | Cumulative fires |
|--------------------------|-------------|----------------------|------------------|
| 1–9 | `*/1` (initial; no change) | 0–9 min | 1–9 |
| 10 | step down to `*/10` | ~10 min | 10 |
| 11–15 | `*/10` | 10–60 min | 11–15 |
| 16 | step down to `*/30` | ~70 min | 16 |
| 17–25 | `*/30` | 70–340 min | 17–25 |
| 26+ | step down to `*/60` (cap) | 340 min+ | 26+ |

Fire counts derived from cumulative cadence, not issue body raw figures:
30 min → 12 fires, 60 min → 15, 120 min → 17, 300 min → 23, 720 min → 31.

**Reset triggers** (the counter file is `rm`'d at):

- Step 0 Case 4 entry (next phase starts — clean per-phase scoping)
- Step 0 Case 1 terminal (plan-complete; next pipeline starts clean)
- Phase 5b plan-complete (alongside `verify-pending-attempts.*` rm)
- Failure Protocol step 5 (post-mortem hygiene)
- `/run-plan stop` (when invoked with a plan-file argument)

**Distinct from Phase 5b's verify-pending one-shot backoff
(`verify-pending-attempts.*`)**: they coexist as mutually-exclusive
runtime states. See SKILL.md Phase 5b sub-step 0b.

**Concurrency note.** Two `finish auto` pipelines on the same plan-file
simultaneously would share the recurring cron prompt and cause counter
ambiguity. Do not launch concurrent `finish auto` pipelines on the same
plan-file. (Same scope as `/run-plan stop`'s system-wide effect.)

**Stop-vs-Case-3 race (DA5).** If you run `/run-plan stop` while a Case
3 cadence-change is in flight (between `CronDelete` and `CronCreate`),
Case 3's `CronCreate` may resurrect the cron after your `stop`. Run
`/run-plan stop` again if needed; the second invocation will catch the
resurrected cron.

**Healthy-phase vs crash-loop ambiguity (DA4).** The per-phase counter
cannot distinguish a healthy long-running phase (implementer agent doing
real work) from a phase that is crash-looping. Both produce the same
backoff signal because `step.run-plan.<id>.implement` is written only at
end-of-phase. This is acceptable: the cost of treating a healthy phase
like a slow one is exactly the cost we are bounding here. When the phase
eventually finishes (crash loop or healthy), the next cron fire reaches
Case 4, which `rm`'s `in-progress-defers.*`, resetting the counter for
the next phase.

**High-severity race recovery.** If `CronDelete` succeeds but
`CronCreate` fails, Case 3 retries inline up to 3 times with a 2-second
`sleep` between attempts. If all 3 retries fail, a
`cron-recovery-needed.<phase>` marker is written and a prominent WARN is
emitted in the turn's final output asking the user to re-invoke
`/run-plan <plan> finish auto`, with an escalation pointer to `/run-plan
stop` + `gh issue create` if the next invocation also fails. The next
user invocation hits the Step 0 sentinel-prelude, which re-attempts
`CronCreate` before case dispatch AND verifies cadence sanity (`*/1,
*/10, */30, */60`) — if a found cron is at an unexpected cadence (e.g.,
a third-party `*/15` cron with the same prompt), the prelude
force-deletes it and creates a fresh `*/1`. The pipeline does NOT
silently stall: the user-visible WARN is the safety mechanism.

**During-phase inspection.** While a phase is in flight, the counter
file at `.zskills/tracking/<pipeline-id>/in-progress-defers.<phase>` is
human-readable (`cat` it to see the current defer count). The five
cleanup sites (Case 4, Case 1, Phase 5b, Failure Protocol, `/run-plan
stop`) remove the file at terminal moments only; during-phase inspection
is always available.

After ensuring the cron exists, output the chunking message:
> Phase <N> of `<plan>` complete (commit `<hash>`).
> Phase <N+1> will fire automatically within ~60 seconds (cron `<job-id>`, recurring `*/1`).
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

