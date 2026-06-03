# /do — Direct Mode (Path C)

Work directly on main; the verification agent commits after tests pass, one logical unit per commit.
### Path C: Direct (`LANDING_MODE="direct"`)

Selected when the user passes `direct` explicitly, when `execution.landing`
in `.claude/zskills-config.json` is `"direct"`, or as the fallback when
no config is present. Work directly on main.

**Claim the issue(s) (when `${#ISSUE_NUMS[@]} -gt 0`).** Direct mode
constructs no `TASK_SLUG`/`PIPELINE_ID` of its own, so synthesize a minimal
`PIPELINE_ID="do.<first-issue>"` (routed through the shared sanitizer)
BEFORE acquiring the `claim-issue.sh` claims. This stops a concurrent
`/fix-issues` cron from double-working the same issue(s). `ISSUE_NUMS` is
propagated from `/do`'s Pre-flight pre-parse (populated only when the
description referenced one or more issues and `--force` overrode the
`/fix-issues` redirect). Skip entirely when `ISSUE_NUMS` is empty (the
common /do direct case — direct mode is rarely issue-driven). The claims
are released in `/do` Phase 5 Report. **Partial-acquire rollback:** if
any acquire returns rc=10 (foreign-held) on issue K, the loop releases
issues 1..K-1 (which this pipeline successfully acquired earlier in the
loop) before exiting — the foreign holder keeps its claim, and this
pipeline leaves no orphaned claims on the issues it had already grabbed.
Same rollback applies on rc=11/2/* failures.

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
  PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "do.${ISSUE_NUMS[0]}")

  # Issue #883 — same-task in-flight guard. Direct mode without an
  # issue number has no stable identity (no TASK_SLUG), so the guard
  # only attaches when an issue number anchors the pipeline_id. A
  # cron re-fire of `Run /do Fix #N ... every ... now` would otherwise
  # double-fire on top of the in-flight turn. Write the sentinel right
  # after the check passes; clear it in /do Phase 5 Report (universal
  # terminal for worktree/direct modes).
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

**Follow existing conventions in all paths:**
- Example models → `/model-design` skill guidelines
- Newsletter entries → existing NEWSLETTER.md format
- Documentation → existing doc style in the repo
- Code → existing patterns in the codebase

**Commit discipline (Paths B and C):**
- **On main (Path C):** commit when the work is complete. Clean, descriptive
  message. `$FULL_TEST_CMD` (resolve via the dual-lane prelude in
  references/canonical-config-prelude.md §1 if you don't already have it in
  your environment) before committing if
  code was touched. If tests fail after two fix attempts on the same error,
  STOP — report what you tried and let the user decide.
- **In worktree (Path B):** the verification agent commits after tests pass.
  One logical unit per commit.

