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
