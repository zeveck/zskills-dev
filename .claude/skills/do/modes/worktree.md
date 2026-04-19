# /do — Worktree Mode (Path B)

Create a named worktree and do the work there; the verification agent commits after tests pass.
### Path B: Worktree mode (`worktree` flag, no `pr`)

Create a named worktree at `../do-<slug>/` using manual `git worktree add`:

```bash
# Compute slug from task description
WORD_COUNT=$(echo "$TASK_DESCRIPTION" | wc -w)
N=$(( WORD_COUNT < 4 ? WORD_COUNT : 4 ))
TASK_SLUG=$(echo "$TASK_DESCRIPTION" | awk "{for(i=1;i<=$N;i++) printf \$i\"-\"; print \"\"}" \
  | sed -E 's/[^a-zA-Z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//' \
  | tr '[:upper:]' '[:lower:]' \
  | cut -c1-30 \
  | sed 's/-$//')
WORKTREE_PATH="../do-${TASK_SLUG}"
# Collision check
if [ -d "$WORKTREE_PATH" ]; then
  TASK_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
  WORKTREE_PATH="../do-${TASK_SLUG}"
fi
git worktree add "$WORKTREE_PATH"
```

Do the work inside the worktree. The verification agent commits after tests pass (one logical unit per commit).

