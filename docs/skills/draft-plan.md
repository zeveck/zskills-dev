# /draft-plan

> Draft a high-quality plan through iterative adversarial review: research, draft, review, devil's-advocate, refine -- repeated until convergence. Output is a plan file ready for `/run-plan` execution.

## What it does

`/draft-plan` turns a description of work into a written plan file you can execute with `/run-plan`. It does this by drafting the plan and then attacking it: one pass researches the problem, another writes a first draft, and then reviewers and a deliberately adversarial "devil's advocate" poke holes in it while a refiner addresses every finding. This review-and-refine cycle repeats until the plan stops accumulating substantive problems (or hits the round budget you set).

The payoff is downstream. `/run-plan` executes a plan faithfully, so the quality of the plan is the quality of the result -- a weak plan executed perfectly is still a weak result. The adversarial drafting is where that quality is bought.

The output is a single plan file with a structure `/run-plan` understands: an overview, a progress tracker, and numbered phases, each with goals, specific work items, design and constraints, and testable acceptance criteria. The file ends with a "Plan Quality" section recording how many rounds ran, whether the plan converged, and any concerns left unresolved.

When run on a repository that protects its main branch, `/draft-plan` does its work in an isolated worktree and commits the finished plan there on a feature branch, rather than leaving it as a loose file. If you pass `auto`, it then opens a pull request for the plan and merges it once checks pass; without `auto`, the commit stays on the branch and you land it yourself.

If the research turns up a task too broad to spec well in one plan -- too many phases, or sub-problems that share nothing -- `/draft-plan` will say so and recommend `/research-and-plan` to decompose it into focused sub-plans instead.

## Typical usage

The common case is a single sentence describing what you want planned:

```
/draft-plan Add dark mode support to the editor
```

You can name the output file (otherwise the path is derived from the description), and you can raise the number of review rounds when the design is hairy:

```
/draft-plan output plans/DARK_MODE.md Add dark mode support
/draft-plan rounds 5 Redesign the solver architecture
```

When you want the plan to land automatically once it is drafted, add `auto`. This is the shape used when chaining straight into execution -- draft the plan, land it, then run it:

```
/draft-plan plans/THERMAL_PLAN.md auto Implement the thermal domain
```

For work where the design itself is still open, start with an interactive conversation before any drafting: `brainstorm` for co-designing a fuzzy idea, or `quiz` for a requirements interview when you know roughly what you want but need the precise requirements drawn out.

```
/draft-plan brainstorm Add a settings panel
/draft-plan quiz Add dark mode support
```

## Companion skills

- **`/run-plan` is the next step.** `/draft-plan` produces a plan file; `/run-plan` executes it. They are sequential, not alternatives -- if you already have a plan file, skip straight to `/run-plan`.
- **`/refine-plan`** adjusts a plan that is already mid-execution when reality has drifted from what the plan assumed -- it sits between `/draft-plan` and `/run-plan` for in-flight corrections.
- **`/draft-tests`** is the test-spec sibling of the plan-authoring family, using the same adversarial drafting to produce test specifications.
- **`/research-and-plan`** is the tool to reach for when a goal is broad enough to decompose into several sub-plans; `/draft-plan` will hand off to it when the task is too big for one plan.
- For a one-commit change where the approach is already settled, `/do` (or `/quickfix`, where the project allows editing main in place) is lighter than drafting a full plan.

## Arguments

```
/draft-plan [output FILE] [rounds N] [auto] [brainstorm|quiz] <description...>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | What the plan should accomplish, in natural language. Can be brief ("add dark mode") or a detailed multi-paragraph brief. Everything after the recognized leading flags is the description. |
| `output FILE` | No | Where to write the plan file. Defaults to a path derived from the description. May be given as `output <path>` or as a bare leading `*.md` token before the description begins. |
| `rounds N` | No | Maximum review-and-refine cycles. Defaults to 3. The process stops early if a round converges with no substantive new issues. |
| `auto` | No | After the plan is committed, open a pull request, run checks, and merge it. Without `auto`, the plan is committed on the feature branch and you land it manually. Recognized anywhere in the arguments. |
| `brainstorm` | No | Run an interactive design dialogue before drafting, then feed what you decided into the research. Recognized only as a leading flag, before the description begins. |
| `quiz` | No | Run an interactive requirements interview before drafting, then seed the research with the requirements it captures. Recognized only as a leading flag, before the description begins. |

`brainstorm` and `quiz` are mutually exclusive -- both are pre-draft interviews, and asking for both at once is an error rather than a silent drop of one. Because they are recognized only at the front of the arguments, a description word like "build a quiz app" does not trigger either mode; to enable a mode you must lead with the flag, not append it.

`auto` mirrors the same token in `/run-plan`, `/do`, `/fix-issues`, and `/quickfix`. It controls only whether the plan lands automatically -- it does not skip the review rounds or the brainstorm/quiz dialogue.

## Examples

```
/draft-plan Add dark mode support to the editor
/draft-plan output plans/DARK_MODE.md Add dark mode support
/draft-plan rounds 5 Redesign the solver architecture
/draft-plan plans/THERMAL_PLAN.md auto Implement the thermal domain
/draft-plan brainstorm Add a settings panel             # interactive design dialogue first
/draft-plan quiz Add dark mode support                  # interactive requirements interview first
/draft-plan output p.md quiz rounds 5 Add dark mode     # quiz in the leading flag cluster, any order
/draft-plan output p.md build a quiz app                # "quiz" here is description, not the flag
/draft-plan add dark mode quiz                          # trailing "quiz" is description, not the flag
```

## Tips & Gotchas

- The plan output is designed to be executed by `/run-plan` -- each phase has clear, testable acceptance criteria.
- Adversarial review means multiple reviewers poke holes in the plan from different angles before it converges; a comfortable review is a useless one.
- Drafting against an existing plan file modernizes it rather than starting blank -- the old plan's intent is treated as research input, and the review checks that nothing from it was lost.
- If a plan does not converge within the round budget, it is still written, with a "remaining concerns" section, and you decide whether to proceed or refine further.
- If the goal is broad enough to decompose into multiple sub-plans, reach for `/research-and-plan` instead.
- Reserve `/draft-plan` for work with non-trivial design surface (integration points, multiple commands, staged phases). A single, settled change is lighter as a `/do` or `/quickfix`.
- Choose between the interview modes by the bottleneck: `brainstorm` when the design surface is fuzzy and you want to co-design it, `quiz` when you know roughly what you want but the requirements need to be drawn out precisely.
