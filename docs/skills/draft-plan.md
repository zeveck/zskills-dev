# /draft-plan

> Draft a high-quality plan through iterative adversarial review: research, draft, review, devil's-advocate, refine -- repeated until convergence. Output is a plan file ready for `/run-plan` execution.

## Usage

```
/draft-plan [output FILE] [rounds N] [auto] <description...>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | What the plan should accomplish, in natural language |
| `output FILE` | No | Output path for the plan file (default: auto-derived from description) |
| `rounds N` | No | Maximum adversarial review rounds (default: 3) |
| `auto` | No | After the Phase 6 worktree commit, dispatch `/land-pr` to push the branch, open a PR, monitor CI, and auto-merge. Without `auto`, the plan is committed in the worktree and the caller lands manually. |

## Examples

```
/draft-plan Add dark mode support to the editor
/draft-plan output plans/DARK_MODE.md Add dark mode support
/draft-plan rounds 5 Redesign the solver architecture
/draft-plan auto Implement undo/redo for the block editor
```

> `auto` mirrors the same token in `/run-plan`, `/do`, `/fix-issues`, and
> `/quickfix`: it triggers the post-commit `/land-pr` auto-merge dispatch. It
> does **not** skip the planning review rounds.

## Common Patterns

- **Standard plan drafting:** `/draft-plan Implement physics simulation blocks` -- research, draft, review cycles until convergence
- **Custom output:** `/draft-plan output plans/PHYSICS_BLOCKS.md Implement physics simulation blocks`
- **More review rounds:** `/draft-plan rounds 5 Redesign the state machine` -- allow up to 5 adversarial review rounds
- **Autonomous (from /research-and-go):** `/draft-plan auto <description>` -- skip confirmation checkpoints

## Tips & Gotchas

- Must run at top level -- internally dispatches reviewer, devil's-advocate, and refiner sub-agents in parallel
- The plan output is designed to be executed by `/run-plan` -- each phase has clear acceptance criteria
- Adversarial review means multiple agents poke holes in the plan from different angles before convergence
- Completed phases from a prior `/run-plan` execution are never modified during refinement
- If the goal is broad enough to decompose into multiple sub-plans, consider `/research-and-plan` instead
- Reserve `/draft-plan` for skills/workflows with non-trivial design surface (integration points, multiple commands, hook interactions) -- thin prompt changes don't need adversarial review
