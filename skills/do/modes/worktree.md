# /do — Worktree Mode (Path B)

Create a named worktree and do the work there; the verification agent commits after tests pass.
### Path B: Worktree mode (`LANDING_MODE="worktree"`)

Selected when the user passes `worktree` explicitly, or when
`execution.landing` in `.claude/zskills-config.json` is `"cherry-pick"`.

Create a named worktree at `/tmp/<project>-do-<slug>/` via `.claude/skills/create-worktree/scripts/create-worktree.sh` (same path convention as `/do pr`, `/fix-issues pr`, and `/run-plan`; `WORKTREE_ROOT` in config overrides `/tmp`).

**Compose $TASK_SLUG (model-layer).** Set shell variable `TASK_SLUG` to a
kebab-case identifier matching `^[a-z0-9]+(-[a-z0-9]+)*$`, ≤30 chars, a
3–5 word summary of the task. Compose from `$TASK_DESCRIPTION`'s essential
verbs/nouns — not a verbatim prefix of the input. Multi-line descriptions
compose the same way as single-line ones: distill the intent, don't
splice lines.

```bash
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
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

# Issue #883 — same-task in-flight guard. Run BEFORE the worktree
# create-with-retry below: the rc=2 retry suffixes ATTEMPT_SLUG when a
# directory already exists, which would mask a legitimate same-task re-
# fire (the second cron fire's TASK_SLUG would be re-derived from the
# same description and naively match the pre-existing worktree, then
# fall into the timestamp-suffix branch and create a second worktree
# alongside the first). The shared sentinel uses the UNSUFFIXED key
# (`do.${TASK_SLUG}`) so the check and the writer agree. Cleared at
# /do Phase 5 Report (universal terminal for worktree mode).
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
if [ -x "$INFLIGHT_HELPER" ]; then
  if bash "$INFLIGHT_HELPER" check do --pipeline-id "$PIPELINE_ID" > /tmp/.do-inflight.$$ 2>/dev/null; then
    rm -f /tmp/.do-inflight.$$
    echo "/do task $PIPELINE_ID in flight; skipping redundant cron re-fire" >&2
    exit 0
  fi
  rm -f /tmp/.do-inflight.$$
  bash "$INFLIGHT_HELPER" write do --pipeline-id "$PIPELINE_ID" || \
    echo "do: WARN — could not write in-flight sentinel (continuing)" >&2
fi
# rc=0 BEFORE the first invocation is MANDATORY (R-M2 regression guard:
# without it, a stale rc=2 from an earlier shell scope would falsely
# trigger the retry block even when the first invocation succeeded).
rc=0
# --no-preflight preserves /do worktree-mode's base-branch semantics
# (branches from user's HEAD, not origin/main).
# --pipeline-id passes the canonical /do pipeline ID explicitly (no env
# var reliance; the script sanitizes internally and writes
# .zskills/tracked).
# No --root: worktree lives under $WORKTREE_ROOT (default /tmp/) with the
# standard ${PROJECT_NAME}-${PREFIX}-${SLUG} layout. This makes /do's
# placement consistent with every other worktree-creating skill and works
# in containerized environments where MAIN_ROOT's parent may not be
# writable.
WORKTREE_PATH=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
  --prefix do --no-preflight \
  --pipeline-id "$PIPELINE_ID" \
  "${ATTEMPT_SLUG}") || rc=$?
if [ "${rc:-0}" = "2" ]; then
  # rc=2 is path-exists collision — retry with timestamp suffix.
  ATTEMPT_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
  WORKTREE_PATH=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
    --prefix do --no-preflight \
    --pipeline-id "$PIPELINE_ID" \
    "${ATTEMPT_SLUG}")
fi
```

**Claim the issue(s) (when `${#ISSUE_NUMS[@]} -gt 0`).** After the
worktree exists and `PIPELINE_ID="do.${TASK_SLUG}"` is set, fan out the
`claim-issue.sh` acquire across every element of `ISSUE_NUMS` BEFORE
dispatching the implementation agent — this stops a concurrent
`/fix-issues` cron from double-working any of the same issues.
`ISSUE_NUMS` is propagated from `/do`'s Pre-flight pre-parse (populated
only when the description referenced one or more issues and `--force`
overrode the `/fix-issues` redirect). Skip entirely when `ISSUE_NUMS` is
empty (the common /do case). The claims are released in `/do` Phase 5
Report (the universal terminal for both auto and non-auto exits).
**Partial-acquire rollback:** if any acquire returns rc=10 (foreign-held)
on issue K, release issues 1..K-1 (acquired earlier in this loop) before
declining. Same rollback applies on rc=11/2/* failures so we never leave
orphaned partial claims.

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
  CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
  _ACQUIRED=()
  for ISSUE_NUM in "${ISSUE_NUMS[@]}"; do
    bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"
    ACQ_RC=$?
    case "$ACQ_RC" in
      0)  _ACQUIRED+=("$ISSUE_NUM") ;;  # acquired (fresh or self-re-entry) — proceed
      10|11|2|*)
        # Partial-acquire rollback: release everything this pipeline grabbed earlier in this loop.
        for _RB in "${_ACQUIRED[@]}"; do
          bash "$CLAIM_HELPER" release "$_RB" --require-pipeline "$PIPELINE_ID"
        done
        case "$ACQ_RC" in
          10) echo "issue #$ISSUE_NUM is being worked by another pipeline; declining (released ${#_ACQUIRED[@]} prior claim(s))." >&2; exit 0 ;;
          11) echo "claim-issue.sh: filesystem error acquiring issue #$ISSUE_NUM (released ${#_ACQUIRED[@]} prior claim(s)); stopping." >&2; exit 1 ;;
          2)  echo "claim-issue.sh: usage error (empty PIPELINE_ID or non-numeric ISSUE_NUM=$ISSUE_NUM; released ${#_ACQUIRED[@]} prior claim(s)) — internal bug; stopping." >&2; exit 1 ;;
          *)  echo "claim-issue.sh: unexpected exit $ACQ_RC acquiring issue #$ISSUE_NUM (released ${#_ACQUIRED[@]} prior claim(s)); stopping." >&2; exit 1 ;;
        esac ;;
    esac
  done
  unset _ACQUIRED _RB
fi
```

Do the work inside the worktree. The verification agent commits after tests pass (one logical unit per commit).

