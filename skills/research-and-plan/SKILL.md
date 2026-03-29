---
name: research-and-plan
argument-hint: "[output FILE] <broad goal description>"
description: >-
  Decompose a broad goal into a sequence of executable sub-plans. Researches
  the domain, identifies sub-problems and dependencies, then produces a
  meta-plan where each phase delegates to /run-plan.
  Usage: /research-and-plan [output FILE] <description...>
---

# /research-and-plan [output FILE] \<description...> — Meta-Plan Decomposer

Breaks broad goals into focused sub-plans, each drafted via `/draft-plan`
and executed via `/run-plan`. The output is a meta-plan file whose phases
are pure delegation — no drafting happens during execution.

**Ultrathink throughout.**

## Arguments

- **output FILE** (optional) — meta-plan output path. Default:
  `plans/<SLUG>_META.md` (slug from description).
- **auto** (optional) — skip the decomposition confirmation checkpoint.
  Proceed directly to drafting after decomposition research. Used by
  `/research-and-go` for fully autonomous operation.
- **description** (required) — everything after recognized keywords.

**Detection:** scan arguments for `output` + path, `auto`, and first
token ending `.md`. Everything else = description. `auto` is stripped
from the description.

**Escalation from `/draft-plan`:** If the invoking context mentions a
research file at `/tmp/draft-plan-research-*.md`, read it — that research
feeds Step 1 and avoids redundant exploration.

## Step 1 — Decomposition Research

Three focused investigations. If a research file was passed from
`/draft-plan`, start from it — validate and extend rather than starting
from scratch.

### 1a. Domain survey — Dispatch Explore agents to map the scope: what the
goal encompasses, what exists already, natural sub-domains, shared
infrastructure needed across sub-problems.

### 1b. Dependency analysis — Build a dependency graph: which sub-problems
are independent (parallelizable), which are sequential, and whether shared
prerequisites exist (e.g., "generalize the port system" before new domains).

### 1c. Scope sizing — Estimate each sub-problem's size. If a sub-plan
would need 8+ phases, split further. Each must be completable by
`/run-plan finish auto` in one session. Mark in-scope vs. out-of-scope.

**Present the decomposition:**
> Decomposition complete. I identified N sub-problems:
> 1. **Sub-problem A** — [one-line description] (est. N phases)
> 2. **Sub-problem B** — [one-line description] (est. M phases, depends on A)
> ...
>
> Dependency graph: A -> B -> D, A -> C (independent of B)
>
> In scope: [list]. Out of scope: [list].

**Without `auto`:** wait for user confirmation. They may reorder, drop,
merge, or add sub-problems. Do NOT proceed until confirmed.

**With `auto`:** present the decomposition for the record, then proceed
directly to Step 2. The user said `auto` — that's approval.

## Step 2 — Draft All Sub-Plans

After user approval, draft each sub-plan by invoking `/draft-plan`.

**DO NOT just skip `/draft-plan` and issue agents to plan directly. If
you do, all work will be thrown out.**
`/draft-plan` dispatches separate reviewer and devil's advocate agents
that catch problems you cannot catch in your own work. Writing a plan
and self-reviewing it is not adversarial review — it's rubber-stamping.

**PROHIBITED — the exact shortcut that keeps failing:**
Do NOT use the Agent tool to dispatch "plan-drafting agents" or "writing
agents" that produce plan files directly. The ONLY way to draft a sub-plan
is via the **Skill tool** with `skill: "draft-plan"`. This has been
violated three separate times, each time producing garbage that was thrown
out. The agent rationalizes "I'll go faster" and skips adversarial review.
It does NOT go faster — it produces plans with 10+ CRITICAL issues that
require full restarts.

For each sub-problem:

1. Determine the sub-plan output path: `plans/<SLUG>_<N>.md` (or let the
   user specify).
2. If research from Step 1 was written to a file, pass that path to the
   `/draft-plan` agent so it has the decomposition context.
3. Dispatch: `/draft-plan output <path> <sub-problem description>`
4. Wait for each `/draft-plan` batch to complete before dispatching the
   next batch (see parallelism rules below).

**Parallelism and resource limits:** Dispatch at most 3 `/draft-plan`
agents concurrently. Wait for each batch to complete before the next.
**While waiting, do NOT draft plans yourself — wait.** The idle time is
the cost of not melting the container. Past failure: 11 parallel agents
caused load average 67, 54 test timeouts, and forced a full restart.

Draft in dependency order:
1. Foundation plan first (alone — everything depends on it)
2. Independent plans in batches of 3
3. Dependent plans after their prerequisites complete

Dependent sub-plans must be drafted after their prerequisites so later
plans can reference earlier plans' actual content.

**Staleness notes for dependent sub-plans.** Sub-plans that depend on
earlier ones get this in their Dependencies section:

```markdown
### Dependencies
- Plan A must be complete. **Note:** This plan was drafted before Plan A
  was implemented. APIs and data structures referenced here are based on
  Plan A's design, not actual code. `/run-plan` may refresh this plan
  before execution.
```

This tells `/run-plan` to offer a plan refresh (interactive) or
auto-refresh (auto mode) before implementing — ensuring the plan reflects
actual code, not predictions.

## Step 2b — Verify All Sub-Plans Were Properly Drafted

**Before proceeding to cross-plan review**, verify that each sub-plan
went through `/draft-plan`'s adversarial process. Two checks:

### Check 1 — Mechanical (grep)

```bash
for plan in plans/<SLUG>_*.md; do
  if ! grep -q '## Plan Quality' "$plan" || ! grep -q '### Round History' "$plan"; then
    echo "FAILED: $plan — missing adversarial review signature"
  fi
done
```

If any plan fails, it was not drafted via `/draft-plan`. Stop and
re-draft it properly.

### Check 2 — Verification agent

Dispatch a verification agent that reads every sub-plan file and checks:

1. `## Plan Quality` section exists with `### Round History` table
2. Round History has at least one round with **non-zero findings** —
   real adversarial review almost always finds issues on round 1. A
   table showing "0 issues | 0 issues" on round 1 is suspicious.
3. The findings described in Round History reference **specific content
   from the plan** (phase names, field names, design decisions) — not
   generic boilerplate like "looks good, no issues found"
4. The plan's phases have concrete work items and acceptance criteria —
   not vague descriptions that suggest a rushed draft

The agent reports pass/fail per plan with evidence. Any plan that fails
must be re-drafted via `/draft-plan` before proceeding.

**Do NOT proceed to Step 3 with unreviewed plans** — the cross-plan
review cannot compensate for plans that were never individually reviewed.

## Step 3 — Cross-Plan Consistency Review (converge until clean)

After all sub-plans are drafted and verified (Step 2b), review the **full
set** for cross-plan consistency. Individual sub-plans were reviewed by `/draft-plan`, but
cross-plan issues (shared schemas, naming collisions, directory conflicts,
storage model disagreements) only emerge when you look at all plans together.

### Each round: dispatch 2+ review agents in parallel

**Reviewer agent** — cross-plan consistency:
- Do all sub-plans agree on shared data structures, schemas, field names?
- Are directory paths, ID prefixes, and namespaces consistent?
- Is the dependency ordering correct?
- Are there missing sub-problems? (Infrastructure, integration, glue?)

**Devil's advocate agent** — structural risks:
- **Wrong split** — would a different decomposition be simpler?
- **Hidden coupling** — shared assumptions that break if one plan changes?
- **Missing glue** — who integrates the sub-plans?
- **Deferred complexity** — hardest part buried in the last sub-plan?

### After each round: apply fixes to the sub-plan files

**This is the critical step that was previously missing.** For every
finding that changes a sub-plan's assumptions, schemas, naming, or
structure — edit the actual sub-plan file. Do NOT just document
resolutions in the meta-plan. The sub-plan files are what `/run-plan`
reads; the meta-plan is an index, not a patch set.

Verify each fix was applied by reading the sub-plan file after editing.

### Convergence

Continue rounds until no CRITICAL or MAJOR issues are found. Minor issues
may be noted for implementation-time resolution. Maximum 3 rounds — if
still finding MAJOR issues after 3 rounds, the decomposition itself may
need restructuring. Report to the user.

## Step 4 — Write the Meta-Plan

After all sub-plans are drafted and the decomposition is reviewed, write
the meta-plan. Every phase is pure delegation — `/run-plan` executes
sub-plans, no `/draft-plan` during execution.

### Meta-plan template

```markdown
# Meta-Plan: <Title>

## Overview
[What this meta-plan accomplishes and the decomposition rationale]

## Decomposition
[Sub-problems identified, dependency graph, scope rationale]

## Sub-Plans
| Plan | Phases | Dependencies | Notes |
|------|--------|--------------|-------|
| [SUB_PLAN_A.md](SUB_PLAN_A.md) | N | None | |
| [SUB_PLAN_B.md](SUB_PLAN_B.md) | M | A | May need refresh after A |

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Implement: <sub-problem A> | ⬚ | | |
| 2 — Implement: <sub-problem B> | ⬚ | | |

## Phase N — Implement: <Sub-problem X>

### Goal
Execute the plan for <sub-problem X>.

### Execution: delegate /run-plan plans/<SUB_PLAN_X>.md finish auto

### Acceptance Criteria
- [ ] All phases in the sub-plan are marked Done
- [ ] All tests pass on main after landing
- [ ] Plan report exists with verification results

### Dependencies
[List prerequisite phases. Dependent sub-plans may auto-refresh.]

## Plan Quality
**Drafting process:** /research-and-plan with cross-plan consistency review
**Sub-plans:** Each drafted via /draft-plan with adversarial review
**Cross-plan review:** N rounds until no CRITICAL/MAJOR issues remain
```

Repeat the `Phase N` template for each sub-problem. First phase has
`Dependencies: None`. Dependent phases list their prerequisites and note
that the sub-plan may auto-refresh to reflect actual implementation.

### Finalization

1. Write the meta-plan to the output path.
2. Update `plans/PLAN_INDEX.md` if it exists (add a row to "Ready to Run").
   If it doesn't exist, suggest `/plans rebuild`.
3. Present the result:
   > Meta-plan written to `plans/<FILE>.md` with N sub-plans.
   > Sub-plans: [list with paths]
   >
   > Execute with: `/run-plan plans/<FILE>.md`
   > Or with scheduling: `/run-plan plans/<FILE>.md auto every 4h now`

## Key Rules

- **Pure delegation in the meta-plan.** Every phase uses
  `### Execution: delegate /run-plan`. No `delegate /draft-plan` — all
  drafting happens upfront in Step 2.
- **User confirms the decomposition.** Step 1 ends with a checkpoint.
  Do not draft sub-plans until the user approves the split.
- **Staleness notes on dependent sub-plans.** Sub-plans drafted before
  their dependencies are implemented get explicit warnings so `/run-plan`
  knows to refresh.
- **Adversarial review targets the decomposition.** Individual sub-plans
  get their own review via `/draft-plan`. Step 3 reviews the split itself.
- **Respect constraints.** No external solvers, no bundlers, no
  dependencies without approval. These apply to every sub-plan.
- **Each sub-plan must be session-completable.** If a sub-plan needs 8+
  phases, split it further.
