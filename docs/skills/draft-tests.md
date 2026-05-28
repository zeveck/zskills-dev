# /draft-tests

> Draft test specifications into an existing plan through iterative adversarial review. Appends a `### Tests` subsection per pending phase via a senior-QE reviewer + devil's-advocate + refiner loop. Completed phases are never modified (checksum-gated).

## Usage

```
/draft-tests <plan-file> [rounds N] [auto] [guidance...]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `plan-file` | Yes | Path to the existing plan file |
| `rounds N` | No | Maximum adversarial review rounds |
| `auto` | No | After the Phase 6 worktree commit, dispatch `/land-pr` to push the branch, open a PR, monitor CI, and auto-merge. Without `auto`, the spec-augmented plan is committed in the worktree and the caller lands manually. |
| `guidance` | No | Additional guidance for the test spec drafting |

## Examples

```
/draft-tests plans/FEATURE_PLAN.md
/draft-tests plans/FEATURE_PLAN.md rounds 5
/draft-tests plans/FEATURE_PLAN.md auto
/draft-tests plans/FEATURE_PLAN.md Focus on edge cases in the parser
```

## Common Patterns

- **Standard test drafting:** `/draft-tests plans/X.md` -- draft test specs for all pending phases
- **With guidance:** `/draft-tests plans/X.md Focus on error handling and edge cases`
- **After /draft-plan:** run `/draft-tests` on the plan to add test specifications before `/run-plan` execution

## Tips & Gotchas

- Must run at top level -- internally dispatches reviewer, devil's-advocate, and refiner sub-agents
- Sister skill to `/draft-plan` -- same adversarial machinery, scoped to test specifications
- Completed phases are NEVER modified -- checksum-gated immutability
- Test gaps in completed phases are surfaced as a new backfill phase, not by modifying existing phases
- The test specs ride along inside the plan phases that `/run-plan` executes -- no companion document needed
- Trailing non-phase sections are preserved byte-identical (stricter than `/refine-plan`)
- `auto` triggers the post-commit `/land-pr` auto-merge dispatch (same token as `/draft-plan`, `/run-plan`, `/do`, `/fix-issues`, `/quickfix`) -- it does not skip the adversarial review rounds
