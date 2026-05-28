# /plans

> Plan dashboard. View plan status, find the next ready plan. For batch execution, see `/work-on-plans`.

## Usage

```
/plans [rebuild | next | details]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | Display the current plan index (highlights top-priority ready plan) |
| `rebuild` | No | Scan all plans, classify, and regenerate the index |
| `next` | No | Show the highest-priority ready-to-run plan with command |
| `details` | No | Show every plan with a one-line description |

## Examples

```
/plans
/plans rebuild
/plans next
/plans details
```

## Common Patterns

- **Check what's ready:** `/plans next` -- see the highest-priority plan ready for execution
- **Full overview:** `/plans details` -- see all plans with descriptions
- **Refresh index:** `/plans rebuild` -- rescan and reclassify all plans
- **Before /work-on-plans:** use `/plans` to review the queue before batch execution

## Tips & Gotchas

- All modes consume the Phase 4 Python aggregator (`collect.py`) -- never re-parses plan frontmatter directly
- The aggregator is the canonical classifier -- this skill is a thin renderer
- For batch execution of plans, use `/work-on-plans` instead
- Plans are classified by category: canary, issue_tracker, reference, executable
- Plan status comes from frontmatter: `active`, `complete`, `landed`, `conflict`
