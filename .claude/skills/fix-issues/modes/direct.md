# /fix-issues — Direct Mode (Per-Issue)

Land each verified fix by rebasing its per-issue worktree branch (`fix-issue-NNN`) onto main, then fast-forward-merging into main. No PR, no cherry-pick extraction. Requires `execution.main_protected: false` (enforced at argument-parse time in Phase 1).

### Direct mode landing

When `LANDING_MODE == direct`, landing replaces cherry-pick with **per-issue
rebase + FF-merge + push**. Each fixed issue is handled independently: one
branch, one FF-merge, one `.zskills/landed` marker per worktree. A failure on one
issue (rebase conflict, FF refused, push error) does NOT block the others —
mark that issue's status and continue to the next.

**Loop over every fixed issue** (and any grouped issue worktrees from
Phase 2). `$FIXED_ISSUES` is the list of issue numbers whose worktrees
have verified commits on `fix-issue-NNN`.

**Catch main up before the loop.** We FF-merge into main repeatedly, so
`MAIN_ROOT` must be on main and current with `origin/main` before the
first merge:

```bash
cd "$MAIN_ROOT"
if ! git checkout main; then
  echo "ERROR: failed to checkout main in $MAIN_ROOT — aborting direct-mode landing." >&2
  # Without main checked out, no FF-merge is possible. Invoke the
  # Failure Protocol — do NOT silently mark every issue as conflict.
  exit 5
fi
git fetch origin main
git pull --ff-only origin main
```

**Rebase before FF-merge** (same pattern as PR mode — keeps the branch
linear and FF-mergeable):

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# Claim-helper path is scoped to this loop body; each terminal arm below
# (plan W2.6c — direct-mode releases) releases the per-issue claim via
# $HELPER. Defined once at the top of the loop body for grep-locality.
HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
for issue in "${FIXED_ISSUES[@]}"; do
  ISSUE_NUM="$issue"
  BRANCH_NAME="fix-issue-${ISSUE_NUM}"
  PROJECT_NAME=$(basename "$PROJECT_ROOT")
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

  # --- Rebase the worktree branch onto latest origin/main ---
  cd "$WORKTREE_PATH"
  # HEAD precondition (symmetric to pr-rebase.sh:82-88; Issue #429).
  # If CWD drifted (forgot a `cd`, wrong worktree active), `git rebase
  # origin/main` would silently retarget the wrong branch and exit 0 —
  # reporting success while $BRANCH_NAME is untouched. Same defense
  # that #397 / pr-rebase.sh installs for the callable surface.
  ACTUAL_HEAD=$(git rev-parse --abbrev-ref HEAD)
  if [ "$ACTUAL_HEAD" != "$BRANCH_NAME" ]; then
    echo "ERROR: fix-issues/direct: CWD is on '$ACTUAL_HEAD', expected '$BRANCH_NAME' — refusing to rebase the wrong branch" >&2
    exit 14
  fi
  git fetch origin main
  PRE_REBASE=$(git rev-parse HEAD)
  if ! git rebase origin/main; then
    if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || \
       [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
      git rebase --abort
    fi
    echo "REBASE CONFLICT for issue #$ISSUE_NUM."
    cat <<LANDED | bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
status: conflict
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: fix-issues
method: direct
branch: $BRANCH_NAME
issue: $ISSUE_NUM
reason: rebase-conflict
LANDED
    # plan W2.6c — release on rebase-conflict terminal arm.
    bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
    continue  # Move to next issue
  fi
  if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
    echo "Main moved — re-verifying issue #$ISSUE_NUM before FF-merge..."
    # Dispatch /verify-changes worktree re-verification.
    # Agent prompt includes "FIRST: cd $WORKTREE_PATH".
    # Re-verification has its own fix cycle (max 2 attempts). If it fails
    # after max attempts, write status: direct-verify-failed and continue.
    # <!-- aspirational: implement when direct-verify-failed terminal lands -->
    # When the direct-verify-failed terminal is implemented as real code
    # (cat <<LANDED ... status: direct-verify-failed ... LANDED followed
    # by continue), add a sibling release call alongside it (plan W2.6c
    # DA3.3): `bash "$HELPER" release "$ISSUE_NUM" --require-pipeline
    # "$PIPELINE_ID" || true`. T2.2c will gain a 5th case at the same time.
  fi

  # --- FF-merge into main ---
  cd "$MAIN_ROOT"
  PRE_FF=$(git rev-parse HEAD)
  if ! git merge --ff-only "$BRANCH_NAME"; then
    # FF refused: either the branch diverged from main after rebase
    # (another commit landed between fetch and merge), or the main repo's
    # working tree has uncommitted changes that overlap with the merge.
    # Either way, skip this issue — same policy as cherry-pick conflict.
    echo "FF-MERGE REFUSED for issue #$ISSUE_NUM (branch diverged or dirty-tree overlap)."
    cat <<LANDED | bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
status: conflict
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: fix-issues
method: direct
branch: $BRANCH_NAME
issue: $ISSUE_NUM
reason: ff-refused
LANDED
    # plan W2.6c — release on FF-refused terminal arm.
    bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
    continue
  fi

  LANDED_COMMITS=$(git log "$PRE_FF"..HEAD --format='%h' | tr '\n' ' ')

  if ! git push origin main; then
    # Push failed — commits are on local main but not on origin. Mark
    # and continue; the next cron turn will see local ahead of origin
    # and retry. Do NOT reset local main; that would discard verified work.
    echo "PUSH FAILED for issue #$ISSUE_NUM after FF-merge (commits on local main, not origin)."
    cat <<LANDED | bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
status: direct-push-failed
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: fix-issues
method: direct
branch: $BRANCH_NAME
issue: $ISSUE_NUM
commits: $LANDED_COMMITS
LANDED
    # plan W2.6c — release on direct-push-failed terminal arm.
    bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
    continue
  fi

  # --- Extract session logs from worktree (same pattern as cherry-pick mode) ---
  if [ -d "$WORKTREE_PATH/.claude/logs" ]; then
    for log in "$WORKTREE_PATH"/.claude/logs/*.md; do
      [ -f ".claude/logs/$(basename "$log")" ] || cp "$log" .claude/logs/
    done
  fi

  # --- Write .zskills/landed marker ---
  cat <<LANDED | bash "$ZSKILLS_SKILLS_ROOT/commit/scripts/write-landed.sh" "$WORKTREE_PATH"
status: full
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: fix-issues
method: direct
branch: $BRANCH_NAME
issue: $ISSUE_NUM
commits: $LANDED_COMMITS
LANDED
  # plan W2.6c — release on FF-merge-success terminal arm (status: full).
  bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true

  echo "Issue #$ISSUE_NUM → direct FF-merge onto main (status: full)"

  # --- Auto-remove fully landed worktree ---
  DIRTY=$(git -C "$WORKTREE_PATH" diff --name-only HEAD)
  UNTRACKED=$(git -C "$WORKTREE_PATH" status --porcelain | \
    grep -v '\.zskills\|\.landed\|\.worktreepurpose\|\.test-results\|\.playwright\|node_modules')

  if [ -z "$DIRTY" ] && [ -z "$UNTRACKED" ]; then
    rm -f "$WORKTREE_PATH/.zskills/landed" "$WORKTREE_PATH/.zskills/worktreepurpose" "$WORKTREE_PATH/.zskills/tracked" \
      "$WORKTREE_PATH/.landed" "$WORKTREE_PATH/.worktreepurpose"  # legacy root paths: dual-read window
    git worktree remove "$WORKTREE_PATH"
    git branch -d "$BRANCH_NAME" 2>/dev/null
  else
    echo "Worktree $WORKTREE_PATH not auto-removed: uncommitted work found"
  fi
done
```

**After the loop — commit extracted logs and run the full test suite:**

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if [ -z "$FULL_TEST_CMD" ]; then
  echo "ERROR: testing.full_cmd not configured. Run /update-zskills." >&2
  exit 1
fi
cd "$MAIN_ROOT"
if [ -n "$(git status --porcelain .claude/logs/)" ]; then
  git add .claude/logs/
  git commit -m "chore: session logs from fix-issues sprint"
  git push origin main
fi

$FULL_TEST_CMD
```

If tests fail after all FF-merges land, invoke the **Failure Protocol** — do not leave broken code on main with the cron still running.

**`.zskills/landed` status values for direct mode:**

| Scenario | status | method | reason |
|----------|--------|--------|--------|
| FF-merge succeeded and pushed | `full` | `direct` | _(not set)_ |
| Rebase conflict | `conflict` | `direct` | `rebase-conflict` |
| FF-merge refused (divergence or dirty-tree overlap) | `conflict` | `direct` | `ff-refused` |
| Push to origin/main failed after FF-merge | `direct-push-failed` | `direct` | _(not set)_ |

In all direct-mode markers, the `issue:` field records which GitHub issue the branch resolves. `/fix-report` reads this field to group commits with issue numbers in the sprint summary.

Closing GH issues and updating trackers are still `/fix-report` actions — even in auto mode (consistent with cherry-pick mode).
