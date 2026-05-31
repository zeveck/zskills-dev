# /do — Direct Mode (Path C)

Work directly on main; the verification agent commits after tests pass, one logical unit per commit.
### Path C: Direct (`LANDING_MODE="direct"`)

Selected when the user passes `direct` explicitly, when `execution.landing`
in `.claude/zskills-config.json` is `"direct"`, or as the fallback when
no config is present. Work directly on main.

**Claim the issue (when `$ISSUE_NUM` is non-empty).** Direct mode
constructs no `TASK_SLUG`/`PIPELINE_ID` of its own, so synthesize a minimal
`PIPELINE_ID="do.<bare-issue>"` (routed through the shared sanitizer)
BEFORE acquiring the `claim-issue.sh` claim. This stops a concurrent
`/fix-issues` cron from double-working the same issue. `$ISSUE_NUM` is
propagated from `/do`'s Pre-flight pre-parse (set only when the description
referenced an issue and `--force` overrode the `/fix-issues` redirect).
Skip entirely when `$ISSUE_NUM` is empty (the common /do direct case —
direct mode is rarely issue-driven). The claim is released in `/do` Phase 5
Report.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if [ -n "${ISSUE_NUM:-}" ]; then
  PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "do.$ISSUE_NUM")
  CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"
  ACQ_RC=$?
  case "$ACQ_RC" in
    0)  : ;;  # acquired (fresh or self-re-entry) — proceed
    10) echo "issue #$ISSUE_NUM is being worked by another pipeline; declining." >&2; exit 0 ;;
    11) echo "claim-issue.sh: filesystem error acquiring issue #$ISSUE_NUM; stopping." >&2; exit 1 ;;
    2)  echo "claim-issue.sh: usage error (empty PIPELINE_ID or non-numeric ISSUE_NUM=$ISSUE_NUM) — internal bug; stopping." >&2; exit 1 ;;
    *)  echo "claim-issue.sh: unexpected exit $ACQ_RC acquiring issue #$ISSUE_NUM; stopping." >&2; exit 1 ;;
  esac
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

