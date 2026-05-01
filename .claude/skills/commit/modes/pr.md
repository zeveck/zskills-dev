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

> Past failure (2026-04-30): agent skipped Step 6 on PR #131 push, read the
> previous inline bash block as suggestion-prose, did one snapshot
> `gh pr checks 131` showing `pending`, reported that in the summary, and
> exited. User discovered the midnight CI flake 20+ minutes later by manual
> polling. **DO NOT skip this step.** The polling logic now lives in
> `scripts/poll-ci.sh` so it must be invoked explicitly — paraphrasing or
> substituting a single `gh pr checks` snapshot is a skill-step skip.

```bash
if [ -n "$PR_URL" ]; then
  PR_NUMBER=$(gh pr view "$PR_URL" --json number --jq '.number')
  bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/poll-ci.sh" "$PR_NUMBER"
fi
```

`scripts/poll-ci.sh` does exactly what the previous inline block did: polls
up to 30s for checks to register, then `timeout 600 gh pr checks --watch` to
block, then re-checks via `gh pr checks` (no `--watch`, exit code is
reliable there) and prints "CI checks passed." (exit 0) or "CI checks
failed. Run /verify-changes to diagnose." (exit 1). See `scripts/poll-ci.sh`
for the implementation and the `--watch`-exit-code rationale.

Note: `PR_NUMBER` is derived from `$PR_URL` returned by `gh pr create` or
`gh pr view "$EXISTING_PR"` — NOT via a bare `gh pr view` call (which relies
on ambient branch autodetect and is subject to race conditions).

**PR mode does NOT:**
- Dispatch fix agents for CI failures
- Write `.landed` markers
- Run Phases 1–5 (all commits must already exist — clean tree is required)

**After Step 6, exit.** Skip Phases 1–5 and 7.

