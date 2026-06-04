# /research-and-go

> Full pipeline in one command: decompose a broad goal into focused sub-plans, draft each with adversarial review, then execute all of them autonomously via `/run-plan`. Walk away.

<details class="flow-cmd" open>
<summary>How it runs — decompose, plan, execute</summary>

<div class="flow">
<div class="flow-step"><p><strong>You</strong> describe the broad goal</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> researches the domain</p></div>
<div class="flow-step"><p>It decomposes the goal into dependent sub-plans</p></div>
<div class="flow-step"><p>Each sub-plan is drafted via <code>/draft-plan</code></p></div>
<div class="flow-step"><p>Every plan is executed via <code>/run-plan</code> — no stop for review</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> runs a combined cross-branch check</p></div>
</div>

</details>

## What it does

`/research-and-go` takes a broad goal — too big to be a single plan — and carries it all the way from idea to landed code without pausing for approval. Given a plain-English description, it researches the domain, breaks the goal into focused sub-plans, identifies the dependencies between them, drafts each one through a round of adversarial review, writes a single meta-plan that ties them together, and then immediately runs that meta-plan to completion. You give it the goal once and it does the rest.

The drafting half is the same machinery as `/research-and-plan`: research agents survey the domain, sub-problems and their dependencies are identified, each sub-plan is sized and written via a dispatched `/draft-plan` agent that subjects it to its own adversarial review, and the result is a meta-plan whose phases each delegate to `/run-plan`. The difference is what happens next. `/research-and-plan` stops there — it hands you a reviewed meta-plan to look over before any code is written. `/research-and-go` does not stop: it continues straight into execution, running the meta-plan's phases one after another, so each sub-plan is implemented, tested, verified, and landed in dependency order.

Because there are no approval checkpoints, the run is autonomous but not reckless. If execution hits a hard problem — a cherry-pick conflict, tests that still fail after two fix cycles, or verification that does not pass — the pipeline stops and reports instead of pushing through. When everything succeeds, the last step is a cross-branch verification pass that checks the combined result of all the sub-plans before the pipeline is considered truly finished.

This skill must run at the top level (typed as a slash command or launched through the `Skill` tool), because it dispatches research, review, and refiner agents of its own. It cannot run as a sub-agent of another skill.

## Usage

```
/research-and-go <description>
```

## Typical usage

The common form is a single broad-goal description in plain English:

```
/research-and-go Add physical modeling support for thermal and mechanical domains
/research-and-go Implement all the missing API endpoints from the gap analysis
/research-and-go Close the runtime deployment parity gap
```

Reach for `/research-and-go` when you trust the pipeline and want end-to-end execution from a single description — decompose, plan, review, and build, all without stopping. If you want a checkpoint to review the meta-plan before any code is written, use `/research-and-plan` instead and run `/run-plan` yourself afterward.

## Companion skills

- **`/research-and-plan`** — the peer skill. It uses the exact same decomposition-and-drafting machinery, but stops once the reviewed meta-plan is ready instead of continuing into execution. Use it when you want to review the plan before building.
- **`/draft-plan`** — dispatched once per sub-plan during the drafting phase. Each call researches and writes one sub-plan and runs it through adversarial review.
- **`/run-plan`** — the executor. The meta-plan's phases each hand off to `/run-plan`, which implements, tests, verifies, and lands each sub-plan in dependency order.
- **`/verify-changes`** — the final gate. After the last sub-plan lands, a cross-branch `/verify-changes` pass checks the combined result before the pipeline is done.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | The broad goal, in natural language. Same format as `/research-and-plan`. |

The description is the only argument. A landing keyword (`pr` or `direct`) appearing as a distinct word inside the description is honored and passed through to `/run-plan` for how each sub-plan lands; with neither word present, landing falls back to the project's configured default.

## Examples

```
/research-and-go Add physical modeling support for thermal and mechanical domains
/research-and-go Implement all the missing API endpoints from the gap analysis
/research-and-go Close the runtime deployment parity gap
```

## Tips & Gotchas

- `/research-and-go` and `/research-and-plan` share the same drafting machinery — the only difference is that `/research-and-go` continues into autonomous execution where `/research-and-plan` stops at the reviewed meta-plan.
- There are no approval checkpoints once it starts. Typing the goal is blanket approval for decomposition, planning, and execution.
- It still stops on hard failure: a cherry-pick conflict, tests failing after two fix cycles, or a failed verification halts the pipeline and reports rather than pushing through.
- It must run at the top level (slash command or `Skill` tool), never as a sub-agent — it dispatches its own research and review agents.
- Sub-plans are built and executed in dependency order; a sub-plan that depends on an earlier one is refreshed before it runs if the earlier work changed its assumptions.
