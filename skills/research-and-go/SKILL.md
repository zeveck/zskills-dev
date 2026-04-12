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
mkdir -p "$MAIN_ROOT/.zskills/tracking"
```

**Check for existing research-and-go pipeline:** If any
`$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.*` files exist, STOP.
Read the file and report its contents — another research-and-go pipeline is
already in progress. Do not proceed unless this is a deliberate re-run (see
Re-run Handling below).

**Create the scoped sentinel:**

```bash
SCOPE=$(echo "$DESCRIPTION" | tr '[:upper:] ' '[:lower:]-' | sed 's/[^a-z0-9-]//g' | cut -c1-30)
printf 'skill=research-and-go\ngoal=%s\nstartedAt=%s\n' "$DESCRIPTION" "$(date -Iseconds)" > "$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.$SCOPE"
```

Where `$DESCRIPTION` is the broad goal passed to this command and `$SCOPE` is a
slugified version for scoping.

**Write `.zskills-tracked` in the main repo root:**

```bash
printf '%s\n' "research-and-go.$SCOPE" > "$MAIN_ROOT/.zskills-tracked"
```

### Re-run Handling

If `pipeline.research-and-go.*` already exists and this is a deliberate re-run
of the same goal:

1. Read the existing `pipeline.research-and-go.*` to confirm the goal matches.
2. Check which `requires.*` files already exist in `$MAIN_ROOT/.zskills/tracking/`.
3. For each existing requirement, check if a corresponding `fulfilled.*` file
   exists. Only create new requirement files for unfulfilled requirements.
4. Touch existing `requires.*` files to refresh their mtime (prevents staleness
   false positives).
5. Overwrite the `pipeline.research-and-go.*` sentinel with a fresh timestamp.

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
  printf 'skill=draft-plan\nindex=%d\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$i" "$(date -Iseconds)" > "$MAIN_ROOT/.zskills/tracking/requires.draft-plan.$i"
  printf 'skill=run-plan\nindex=%d\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$i" "$(date -Iseconds)" > "$MAIN_ROOT/.zskills/tracking/requires.run-plan.$i"
done
```

Also create a requirement for the meta-plan execution itself:

```bash
printf 'skill=run-plan\nid=meta\nrequiredBy=research-and-go\ncreatedAt=%s\n' "$(date -Iseconds)" > "$MAIN_ROOT/.zskills/tracking/requires.run-plan.meta"
```

Replace `1 2 ... N` with the actual sub-plan indices. The `draft-plan`
requirements track the planning phase; the `run-plan` requirements track
execution.

**Pass tracking IDs to child skills:** When dispatching `/run-plan` for each
sub-plan, include the tracking index so child skills can mark their
corresponding requirement as completed. For example, include
`tracking-index=3` in the dispatch prompt for sub-plan 3.

## Step 2 — Execute

Immediately run:

```
/run-plan <meta-plan-path> finish auto
```

This executes all implementation phases sequentially — each delegating
to `/run-plan` on the corresponding sub-plan. Full verification,
testing, and landing at each phase.

## Step 3 — Report

When `/run-plan finish auto` completes (or fails), report:

> **`/research-and-go` complete.**
> Goal: [original description]
> Sub-plans: N drafted, M executed successfully
> Meta-plan: `plans/<META_PLAN>.md`
> Report: `reports/plan-<slug>.md`
>
> [If any phase failed: which one and why]

### Pipeline Cleanup

After successful completion (all phases passed), clean up all tracking files:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
rm -f "$MAIN_ROOT/.zskills/tracking"/*
```

After the pipeline completes, clean up:

```bash
rm -f "$MAIN_ROOT/.zskills-tracked"
rm -f "$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.$SCOPE"
```

If any phase failed, do NOT clean up tracking files — they serve as a record of
what was accomplished and what remains, enabling a re-run to pick up where this
run left off (see Step 0 Re-run Handling).

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
