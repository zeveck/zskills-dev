# /do — Worktree Mode (Path B)

Create a named worktree and do the work there; the verification agent commits after tests pass.
### Path B: Worktree mode (`LANDING_MODE="worktree"`)

Selected when the user passes `worktree` explicitly, or when
`execution.landing` in `.claude/zskills-config.json` is `"cherry-pick"`.

Create a named worktree at `${realpath(MAIN_ROOT/../)}/do-<slug>/` via `scripts/create-worktree.sh`:

```bash
# Compute slug from task description
WORD_COUNT=$(echo "$TASK_DESCRIPTION" | wc -w)
N=$(( WORD_COUNT < 4 ? WORD_COUNT : 4 ))
TASK_SLUG=$(echo "$TASK_DESCRIPTION" | awk "{for(i=1;i<=$N;i++) printf \$i\"-\"; print \"\"}" \
  | sed -E 's/[^a-zA-Z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//' \
  | tr '[:upper:]' '[:lower:]' \
  | cut -c1-30 \
  | sed 's/-$//')

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
ATTEMPT_SLUG="${TASK_SLUG}"
PIPELINE_ID="do.${TASK_SLUG}"
# rc=0 BEFORE the first invocation is MANDATORY (R-M2 regression guard:
# without it, a stale rc=2 from an earlier shell scope would falsely
# trigger the retry block even when the first invocation succeeded).
rc=0
# --root ../ resolves against $MAIN_ROOT (Phase 1a CWD-invariance).
# --no-preflight preserves /do worktree-mode's base-branch semantics
# (branches from user's HEAD, not origin/main).
# --pipeline-id passes the canonical /do pipeline ID explicitly (no env
# var reliance; the script sanitizes internally and writes
# .zskills-tracked).
WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
  --prefix do --root ../ --no-preflight \
  --pipeline-id "$PIPELINE_ID" \
  "${ATTEMPT_SLUG}") || rc=$?
if [ "${rc:-0}" = "2" ]; then
  # rc=2 is path-exists collision — retry with timestamp suffix.
  ATTEMPT_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
  WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
    --prefix do --root ../ --no-preflight \
    --pipeline-id "$PIPELINE_ID" \
    "${ATTEMPT_SLUG}")
fi
```

Do the work inside the worktree. The verification agent commits after tests pass (one logical unit per commit).

