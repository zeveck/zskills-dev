# /do — PR Mode (Path A)

Full end-to-end PR flow: create branch, worktree, dispatch agents, open the PR, poll CI, then write the landing marker.
### Path A: PR mode (`pr` flag)

**This path replaces the normal Phase 2–5 flow entirely. After the PR is created, skip to Phase 5 Report.**

**Step A1 — Compute task slug:**
```bash
# N = min(4, word_count) words from TASK_DESCRIPTION
WORD_COUNT=$(echo "$TASK_DESCRIPTION" | wc -w)
N=$(( WORD_COUNT < 4 ? WORD_COUNT : 4 ))
TASK_SLUG=$(echo "$TASK_DESCRIPTION" | awk "{for(i=1;i<=$N;i++) printf \$i\"-\"; print \"\"}" \
  | sed -E 's/[^a-zA-Z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//' \
  | tr '[:upper:]' '[:lower:]' \
  | cut -c1-30 \
  | sed 's/-$//')
```

**Step A2 — Collision check (BEFORE deriving BRANCH_NAME or WORKTREE_PATH):**
```bash
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
if [ -d "/tmp/${PROJECT_NAME}-do-${TASK_SLUG}" ]; then
  TASK_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
fi
```

**Step A3 — Derive BRANCH_NAME and WORKTREE_PATH from (possibly suffixed) TASK_SLUG:**
```bash
BRANCH_PREFIX=$(jq -r '.execution.branch_prefix // "feat/"' .claude/zskills-config.json 2>/dev/null || echo "feat/")
BRANCH_NAME="${BRANCH_PREFIX}do-${TASK_SLUG}"
WORKTREE_PATH="/tmp/${PROJECT_NAME}-do-${TASK_SLUG}"
```

**Step A4 — ff-merge main + worktree creation:**
```bash
git fetch origin main 2>/dev/null \
  || echo "WARNING: git fetch origin main failed — worktree will use cached origin/main (may be stale)"
git merge --ff-only origin/main 2>/dev/null \
  || echo "WARNING: local main not fast-forwarded — worktree uses local main as-is"
git worktree prune
# /do expects a fresh branch per task — no legitimate resume.
bash scripts/worktree-add-safe.sh "$BRANCH_NAME" "$WORKTREE_PATH" main
```

**Step A5 — Write tracking marker immediately after worktree creation:**
```bash
# Route TASK_SLUG through the shared sanitizer before constructing
# PIPELINE_ID (per Phase 1 design doc). Collapses any character outside
# [a-zA-Z0-9._-] into `_` and truncates to 128 bytes.
TASK_SLUG=$(bash scripts/sanitize-pipeline-id.sh "$TASK_SLUG")
PIPELINE_ID="do.${TASK_SLUG}"
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```
Do NOT echo `ZSKILLS_PIPELINE_ID=do.${TASK_SLUG}` in the main session — write only to the worktree file.

**Step A6 — Dispatch implementation agent (wait for completion):**

**Before dispatching:** Check `agents.min_model` in `.claude/zskills-config.json`. If set,
use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch with a
lower-ordinal model than the configured minimum.

Dispatch an Agent (without `isolation: "worktree"` — the worktree already exists) with this prompt:

```
You are implementing: $TASK_DESCRIPTION

FIRST: cd $WORKTREE_PATH
All work happens in that directory. Do NOT work in any other directory.
You are on branch $BRANCH_NAME (already checked out in the worktree).

Implement the task. Commit changes when done:
- Stage files by name (not git add .)
- Do NOT commit to main
- Commit message should summarize what was implemented

Check agents.min_model in .claude/zskills-config.json before dispatching
any sub-agents. Use that model or higher (haiku=1 < sonnet=2 < opus=3).
```

Wait for the implementation agent to complete. If the agent reports failure or exits without committing:
```bash
cat > "$WORKTREE_PATH/.landed" <<LANDED
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: do
branch: $BRANCH_NAME
LANDED
```
Exit with error directing the user to inspect `$WORKTREE_PATH`.

**Step A7 — Rebase + push + PR creation (after implementation agent completes):**
```bash
cd "$WORKTREE_PATH"
# Rebase onto latest main before push
git fetch origin main
git rebase origin/main || { echo "ERROR: Rebase conflict. Resolve manually in $WORKTREE_PATH."; exit 1; }

git push -u origin "$BRANCH_NAME"

# PR body: explicit title and body, not --fill
PR_TITLE="do: $(echo "$TASK_DESCRIPTION" | cut -c1-60)"
PR_BODY="Task: ${TASK_DESCRIPTION}

Worktree: ${WORKTREE_PATH}
Commits: $(git log origin/main..HEAD --format='%h %s' | head -10)"

EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
  echo "PR already exists: $PR_URL"
else
  PR_URL=$(gh pr create --base main --head "$BRANCH_NAME" \
    --title "$PR_TITLE" --body "$PR_BODY")
  echo "Created PR: $PR_URL"
fi
```

**Step A8 — CI poll (report only, no fix cycle):**
```bash
if [ -n "$PR_URL" ]; then
  PR_NUMBER=$(gh pr view "$PR_URL" --json number --jq '.number')
  CHECK_COUNT=0
  for _i in 1 2 3; do
    CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
    [ "$CHECK_COUNT" != "0" ] && break
    sleep 10
  done
  CI_STATUS="none"
  if [ "$CHECK_COUNT" != "0" ]; then
    # `gh pr checks --watch` exit code is unreliable across gh versions
    # (can return 0 even when a check failed). Use --watch only to block
    # until completion; then re-check with `gh pr checks` (no --watch),
    # which DOES signal via exit code reliably.
    timeout 600 gh pr checks "$PR_NUMBER" --watch 2>/dev/null
    if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
      CI_STATUS="passed"
      echo "CI checks passed."
    else
      CI_STATUS="failed"
      echo "CI checks failed. Inspect the PR to diagnose failures."
    fi
  fi
fi
```

**Step A9 — Write `.landed` marker:**
```bash
# Check if PR was auto-merged. If gh pr view fails (network / auth / rate),
# retry up to 3 times with 2s/4s backoff (6s max). On total failure, record
# UNKNOWN and propagate pr-state-unknown into .landed so state-loss is
# visible and downstream tooling can detect the literal string.
PR_STATE="UNKNOWN"
for attempt in 1 2 3; do
  if STATE_OUT=$(gh pr view "$PR_URL" --json state --jq '.state' 2>&1); then
    PR_STATE="$STATE_OUT"
    break
  fi
  echo "WARN: gh pr view attempt $attempt failed: $STATE_OUT" >&2
  [ $attempt -lt 3 ] && sleep $((attempt * 2))
done
if [ "$PR_STATE" = "UNKNOWN" ]; then
  echo "ERROR: gh pr view failed 3 times for $PR_URL. Recording pr-state-unknown." >&2
  LANDED_STATUS="pr-state-unknown"
elif [ "$PR_STATE" = "MERGED" ]; then
  LANDED_STATUS="landed"
elif [ "$CI_STATUS" = "failed" ]; then
  LANDED_STATUS="pr-ci-failing"
else
  LANDED_STATUS="pr-ready"
fi

cat > "$WORKTREE_PATH/.landed" <<LANDED
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: do
branch: $BRANCH_NAME
pr: $PR_URL
LANDED
```

After writing `.landed`, output the Phase 5 PR report and **exit** (skip Phases 3-4).

