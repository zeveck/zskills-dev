# /do — Worktree Mode (Path B)

Create a named worktree and do the work there; the verification agent commits after tests pass.
### Path B: Worktree mode (`LANDING_MODE="worktree"`)

Selected when the user passes `worktree` explicitly, or when
`execution.landing` in `.claude/zskills-config.json` is `"cherry-pick"`.

Create a named worktree at `/tmp/<project>-do-<slug>/` via `scripts/create-worktree.sh` (same path convention as `/do pr`, `/fix-issues pr`, and `/run-plan`; `WORKTREE_ROOT` in config overrides `/tmp`).

**Compose $TASK_SLUG (model-layer).** Set shell variable `TASK_SLUG` to a
kebab-case identifier matching `^[a-z0-9]+(-[a-z0-9]+)*$`, ≤30 chars, a
3–5 word summary of the task. Compose from `$TASK_DESCRIPTION`'s essential
verbs/nouns — not a verbatim prefix of the input. Multi-line descriptions
compose the same way as single-line ones: distill the intent, don't
splice lines.

```bash
if [ -z "${TASK_SLUG:-}" ]; then
  echo "ERROR: TASK_SLUG not set — model-layer composition step skipped." >&2
  exit 5
fi
if ! [[ "$TASK_SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ ${#TASK_SLUG} -gt 30 ]; then
  echo "ERROR: TASK_SLUG must match ^[a-z0-9]+(-[a-z0-9]+)*\$ and be ≤30 chars (got '$TASK_SLUG')." >&2
  exit 2
fi

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
ATTEMPT_SLUG="${TASK_SLUG}"
PIPELINE_ID="do.${TASK_SLUG}"
# rc=0 BEFORE the first invocation is MANDATORY (R-M2 regression guard:
# without it, a stale rc=2 from an earlier shell scope would falsely
# trigger the retry block even when the first invocation succeeded).
rc=0
# --no-preflight preserves /do worktree-mode's base-branch semantics
# (branches from user's HEAD, not origin/main).
# --pipeline-id passes the canonical /do pipeline ID explicitly (no env
# var reliance; the script sanitizes internally and writes
# .zskills-tracked).
# No --root: worktree lives under $WORKTREE_ROOT (default /tmp/) with the
# standard ${PROJECT_NAME}-${PREFIX}-${SLUG} layout. This makes /do's
# placement consistent with every other worktree-creating skill and works
# in containerized environments where MAIN_ROOT's parent may not be
# writable.
WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
  --prefix do --no-preflight \
  --pipeline-id "$PIPELINE_ID" \
  "${ATTEMPT_SLUG}") || rc=$?
if [ "${rc:-0}" = "2" ]; then
  # rc=2 is path-exists collision — retry with timestamp suffix.
  ATTEMPT_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
  WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
    --prefix do --no-preflight \
    --pipeline-id "$PIPELINE_ID" \
    "${ATTEMPT_SLUG}")
fi
```

Do the work inside the worktree. The verification agent commits after tests pass (one logical unit per commit).

