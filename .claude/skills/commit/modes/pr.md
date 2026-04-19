# /commit pr — PR Subcommand Mode

Loaded by /commit when the first argument token is `pr`; replaces Phases 1–5 to push the current branch and open a PR.
## Phase 6 (PR subcommand) — PR Mode (if `pr` is the first token)

**This phase runs INSTEAD OF Phases 1–5 when `pr` is the first token.**
It pushes the current branch and creates a PR to main.

**Step 1 — Pre-check: clean working tree required:**
```bash
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  echo "ERROR: Working tree has uncommitted changes."
  echo "Run \`/commit\` first to create a commit, then \`/commit pr\` to push and create the PR."
  exit 1
fi
```

**Step 2 — Branch guard:**
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Cannot create PR from main. Create a feature branch first."
  exit 1
fi
```

**Step 3 — Rebase onto latest main before pushing:**
```bash
git fetch origin main
git rebase origin/main
if [ $? -ne 0 ]; then
  echo "ERROR: Rebase conflict. Resolve manually, then re-run \`/commit pr\`."
  exit 1
fi
```

**Step 4 — Push:**
```bash
git push -u origin "$BRANCH"
```

**Step 5 — Create PR:**
```bash
# PR title: strip branch prefix, convert hyphens to spaces
BRANCH_SHORT="${BRANCH##*/}"  # remove prefix like feat/
PR_TITLE=$(echo "$BRANCH_SHORT" | tr '-' ' ' | sed 's/\b./\u&/g')
# Body: recent commits since divergence from origin/main (not local main — may be stale after rebase)
PR_BODY=$(git log origin/main..HEAD --format='- %h %s' | head -15)

EXISTING_PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
  echo "PR already exists: $PR_URL"
else
  PR_URL=$(gh pr create --base main --head "$BRANCH" \
    --title "$PR_TITLE" --body "$PR_BODY")
  echo "Created PR: $PR_URL"
fi
```

**Step 6 — Poll CI checks (report only, no fix cycle):**
```bash
if [ -n "$PR_URL" ]; then
  PR_NUMBER=$(gh pr view "$PR_URL" --json number --jq '.number')
  CHECK_COUNT=0
  for _i in 1 2 3; do
    CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
    [ "$CHECK_COUNT" != "0" ] && break
    sleep 10
  done
  if [ "$CHECK_COUNT" != "0" ]; then
    # `gh pr checks --watch` exit code is unreliable across gh versions
    # (can return 0 even when a check failed). Use --watch only to block
    # until completion; then re-check with `gh pr checks` (no --watch),
    # which DOES signal via exit code reliably.
    timeout 600 gh pr checks "$PR_NUMBER" --watch 2>/dev/null
    if gh pr checks "$PR_NUMBER" >/dev/null 2>&1; then
      echo "CI checks passed."
    else
      echo "CI checks failed. Run /verify-changes to diagnose."
    fi
  fi
fi
```

Note: `PR_NUMBER` is derived from `$PR_URL` returned by `gh pr create` or
`gh pr view "$EXISTING_PR"` — NOT via a bare `gh pr view` call (which relies
on ambient branch autodetect and is subject to race conditions).

**PR mode does NOT:**
- Dispatch fix agents for CI failures
- Write `.landed` markers
- Run Phases 1–5 (all commits must already exist — clean tree is required)

**After Step 6, exit.** Skip Phases 1–5 and 7.

