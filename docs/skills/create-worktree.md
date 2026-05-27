# /create-worktree

> Create a git worktree for agent work. Thin wrapper around `create-worktree.sh` -- owns prefix-derived path, optional branch-name override, pre-flight prune+fetch+ff-merge, safe worktree-add, and sanitized tracking writes.

## Usage

```
/create-worktree <slug> [--prefix P] [--branch-name REF] [--from B] [--root R]
                 [--purpose TEXT] [--pipeline-id ID] [--allow-resume] [--no-preflight]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `slug` | Yes | Short identifier for the worktree |
| `--prefix P` | No | Prefix for the worktree path (e.g., `fix-issue`, `add-block`) |
| `--branch-name REF` | No | Override the auto-generated branch name |
| `--from B` | No | Base branch to create the worktree from |
| `--root R` | No | Root directory for the worktree |
| `--purpose TEXT` | No | Human-readable purpose description |
| `--pipeline-id ID` | No | Pipeline ID for tracking (required for Tier 1 callers) |
| `--allow-resume` | No | Allow resuming an existing worktree |
| `--no-preflight` | No | Skip the prune+fetch+ff-merge preflight |

## Two-Tier Contract

### Tier 1 -- Bash callers inside other skills

Skills like `/run-plan`, `/fix-issues`, `/do` know their pipeline ID and **must pass it via `--pipeline-id`**. The script rejects invocations without the flag.

### Tier 2 -- User / Claude slash command

Users don't need to know about pipeline IDs. When omitted, Claude synthesizes `create-worktree.<slug>` automatically.

## Examples

```
/create-worktree my-feature
/create-worktree my-feature --prefix fix-issue --pipeline-id fix-issues.sprint-123
/create-worktree my-feature --branch-name custom/branch-name
/create-worktree my-feature --from develop --purpose "Experimental feature work"
/create-worktree my-feature --allow-resume
```

## Common Patterns

- **User worktree:** `/create-worktree my-feature` -- creates a worktree with auto-generated pipeline ID
- **Skill integration:** called internally by `/run-plan`, `/fix-issues`, `/do`, `/add-block`, etc. with `--pipeline-id`
- **Resume existing:** `/create-worktree my-feature --allow-resume` -- reuse an existing worktree if present

## Tips & Gotchas

- Prints the worktree path on stdout -- callers capture it to `cd` into
- The script handles pre-flight (prune, fetch, ff-merge), worktree creation, and `.zskills-tracked` write
- `--pipeline-id` is required for Tier 1 (skill) callers; script exits with rc 5 without it
- `--no-preflight` skips the fetch/prune/ff-merge for speed when the caller has already done it
- Worktrees are created under `/tmp/<project>-<prefix>-<slug>/` by default
- The underlying script is at `.claude/skills/create-worktree/scripts/create-worktree.sh`
