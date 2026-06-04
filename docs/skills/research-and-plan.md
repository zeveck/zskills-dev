# /research-and-plan

> Decompose a broad goal into a sequence of executable sub-plans. Researches the domain, identifies sub-problems and dependencies, and produces a meta-plan whose phases each hand off to `/run-plan`. Stops once the meta-plan is ready for review.

<details class="flow-cmd" open>
<summary>How it runs — decompose, then stop for review</summary>

<div class="flow">
<div class="flow-step"><p><strong>You</strong> describe the broad goal</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> researches the domain</p></div>
<div class="flow-step"><p>It decomposes the goal into dependent sub-plans</p></div>
<div class="flow-step"><p><strong>You</strong> confirm the split</p></div>
<div class="flow-step"><p>Each sub-plan is drafted via <code>/draft-plan</code> (its own reviewer, devil's-advocate, and refiner subagents)</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> writes a meta-plan and stops for your review</p></div>
</div>

</details>

## What it does

`/research-and-plan` takes a goal that's too large for a single plan and breaks it into a set of smaller, focused sub-plans. It researches the domain first — surveying what the goal covers, what already exists, and which pieces are genuinely separate sub-problems — then works out how those pieces depend on each other and roughly how big each one is. Sub-problems that would be too large to finish in one sitting get split further.

It then presents the proposed split — the sub-problems, their dependency order, and what's in or out of scope — and (unless you tell it otherwise) waits for you to confirm before drafting anything. You can reorder, drop, merge, or add sub-problems at this checkpoint.

Once the split is confirmed, `/research-and-plan` drafts each sub-plan, one at a time, by running `/draft-plan` on it — so each sub-plan goes through the same adversarial review a standalone plan would. It drafts in dependency order, foundation first, so later sub-plans can reference what earlier ones actually contain. After all the sub-plans exist, it reviews the whole set together for cross-plan problems that only show up when you look at every plan at once — clashing names, disagreeing data structures, conflicting directories, or a missing piece of integration glue — and edits the sub-plan files to fix what it finds.

Finally it writes the **meta-plan**: an index file whose phases are pure hand-offs. Each phase points `/run-plan` at one sub-plan. No drafting happens later; all of it is done up front. `/research-and-plan` stops here, with the meta-plan and its sub-plans ready for you to review and then execute.

`/research-and-plan` and `/research-and-go` are the same drafting machinery. The difference is where they stop: `/research-and-plan` stops once the meta-plan is ready for review, while `/research-and-go` continues straight on into executing every sub-plan. Reach for `/research-and-plan` when you want a checkpoint to look the decomposition over before any execution begins.

## Usage

```
/research-and-plan [output FILE] [auto] <broad goal description>
```

## Typical usage

The common form is a plain-English goal, optionally with an output path or an `auto` flag:

```
/research-and-plan Build a complete physics simulation engine
/research-and-plan output plans/PHYSICS_META.md Build physics simulation
/research-and-plan auto Implement undo/redo for the block editor
```

A goal on its own runs the full flow and pauses at the decomposition checkpoint for your confirmation. Add `output FILE` to choose where the meta-plan is written. Add `auto` to skip that checkpoint and go straight from research into drafting. When you're done, run `/run-plan` on the meta-plan to execute it.

## Companion skills

- **`/research-and-go`** — the peer skill. Same research-and-decompose machinery; `/research-and-plan` stops after the meta-plan is ready for review, while `/research-and-go` continues into executing the sub-plans. Use `/research-and-plan` when you want to review the split first.
- **`/draft-plan`** — run on each sub-problem to produce a reviewed sub-plan. `/research-and-plan` calls it once per sub-problem. If `/draft-plan` decides a goal is too broad for a single plan, it escalates here.
- **`/run-plan`** — what every phase of the finished meta-plan hands off to. Run it on the meta-plan to execute the sub-plans.
- **`/refine-plan`** — adjusts a sub-plan that has drifted from reality once execution is underway.
- **`/plans`** — the plan catalog; the meta-plan and its sub-plans show up there for you to find and queue.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | The broad goal, in natural language |
| `output FILE` | No | Where to write the meta-plan (default: an auto-derived `<slug>_META.md` in your plans directory) |
| `auto` | No | Skip the decomposition confirmation checkpoint and go straight to drafting |

The `auto` flag is documented in the skill body even though the `argument-hint` omits it; it is a real, accepted argument. `/research-and-go` passes it through when it drives `/research-and-plan` for fully autonomous operation.

Arguments are detected positionally: an `output` keyword plus a path, the word `auto`, and the first token ending in `.md` are pulled out as options; everything else is the goal description.

## Examples

```
/research-and-plan Build a complete physics simulation engine
/research-and-plan output plans/PHYSICS_META.md Build physics simulation
/research-and-plan auto Implement undo/redo for the block editor
```

## Common Patterns

- **Standard decomposition:** `/research-and-plan Build physics blocks` — research, decompose, pause for confirmation, then draft each sub-plan.
- **Custom output path:** `/research-and-plan output plans/PHYSICS_META.md Build physics blocks` — write the meta-plan where you want it.
- **Review before execution:** produce the meta-plan, review the split and the sub-plans, then run `/run-plan` on the meta-plan to execute.
- **Hands-off decomposition:** `/research-and-plan auto Implement undo/redo` — skip the confirmation checkpoint and draft straight through.

## Tips & Gotchas

- `/research-and-plan` runs as a top-level command — type it yourself or have an orchestrating skill invoke it. It cannot run as a dispatched sub-agent, because it relies on launching its own research and review agents.
- The meta-plan is an index: every phase hands off to `/run-plan` on one sub-plan. None of the sub-plans are drafted later — all the drafting happens up front before the meta-plan is written.
- Each sub-plan is sized to be finishable by `/run-plan` in one session. A sub-problem that would need eight or more phases is split further.
- A sub-plan drafted before the sub-plan it depends on has been built carries a note saying so, so `/run-plan` knows it may need to refresh the plan against the real code before executing.
- For a fully autonomous run that decomposes *and* executes without stopping, use `/research-and-go` instead.
- If `/draft-plan` sends you here because a goal turned out to be too broad for a single plan, the research it already did is carried over so the work isn't repeated.
