---
name: commit
disable-model-invocation: true
description: >-
  Safe commit workflow with optional scope hint. Inventories all changes,
  classifies related vs. unrelated files, traces dependencies, protects
  other agents' work, and optionally pushes or lands worktree commits.
  Usage: /commit [pr] [scope] [push|land]
argument-hint: "[pr] [scope] [push|land]"
---

# /commit [pr] [scope] [push|land] — Safe Commit Workflow

Commit current work without picking up or harming unrelated changes.

**Arguments:**
- `/commit` — commit only, infer scope from diffs
- `/commit skill updates` — commit, scope guided by "skill updates"
- `/commit push` — commit and push to remote
- `/commit parser reset button fix push` — scope-guided commit + push
- `/commit land` — cherry-pick worktree commits into main (worktree only)
- `/commit pr` — push current branch and create a PR to main (requires clean working tree)
- `/commit pr fix pr comments` — PR mode with scope hint "fix pr comments"

**Parsing:** `pr` is recognized ONLY when it is the **FIRST token** in
`$ARGUMENTS`. This prevents false-triggering on scope hints that contain
"pr" mid-string. `push` and `land` are reserved keywords for non-PR mode.

```bash
FIRST_TOKEN=$(echo "$ARGUMENTS" | awk '{print $1}')
if [[ "$FIRST_TOKEN" == "pr" ]]; then
  # PR subcommand mode
  SCOPE_HINT=$(echo "$ARGUMENTS" | cut -d' ' -f2-)  # rest after 'pr' (may be empty)
  # ... see Phase 6 (PR mode) below
fi
```

Disambiguation:
- `/commit pr` → PR mode (first token is `pr`)
- `/commit pr comments fix` → PR mode (first token is `pr`), scope hint: "comments fix"
- `/commit fix pr format` → scope hint "fix pr format", regular commit (first token is "fix")

Examples:
- `/commit` → scope: *(none)*, action: commit
- `/commit codegen fixes` → scope: "codegen fixes", action: commit
- `/commit skill updates push` → scope: "skill updates", action: commit + push
- `/commit push` → scope: *(none)*, action: commit + push
- `/commit land` → scope: *(none)*, action: land
- `/commit parser fixes land` → scope: "parser fixes", action: land
- `/commit pr` → action: PR mode (push + create PR)
- `/commit pr fix pr comments` → PR mode, scope hint: "fix pr comments"

## Phase 1 — Inventory

Run these in parallel:

```bash
git status -s            # all changes (never use -uall)
git diff                 # unstaged changes
git diff --cached        # staged changes
git log --oneline -10    # recent commit style
```

Also determine context:
- **Which branch** am I on?
- **Am I in a worktree?** (`git rev-parse --show-toplevel` differs from main repo)
- **Is there a remote tracking branch?**

## Phase 2 — Classify Changes

For every changed and untracked file from `git status -s`, decide:

1. **Related to current work** — include in this commit
2. **Unrelated (other agents/sessions)** — leave alone, do NOT touch

### If a scope hint was provided

The scope hint tells you what this commit is about. Use it to drive
classification:

1. **Keyword grep** — search the file list for scope-related terms:
   ```bash
   git status -s | grep -i <keyword>
   ```
   For `/commit skill updates`, grep for `skill`, `SKILL`, `.claude/skills/`.
   For `/commit codegen fixes`, grep for `codegen`, `block-emitter`, `Rust`.

2. **Diff-check remaining files** — for files that don't match the keyword,
   read the diff to confirm they're unrelated. Some related files won't match
   a simple grep (e.g., a memory file updated alongside skill changes).

3. **Confidence is higher** — with a scope hint, you can be more decisive
   about what's in vs. out. Without one, you have to read every diff and infer.

### If no scope hint was provided

Fall back to the original approach:

- Read the diff for each modified file. Does it relate to what we worked on?
- For untracked files (`??`): are they part of this feature? If unsure, ask.

### Always

- **Context compaction warning:** Do NOT rely on session memory for "what I
  changed." Context compaction creates artificial boundaries. Always classify
  from the actual diffs and the scope hint.
- **If a file has mixed changes** (yours + someone else's): STOP. Tell the
  user which file and what the mixed changes are. Ask what to do. Do NOT
  attempt to split hunks or selectively stage — that risks losing work.

## Phase 3 — Trace Dependencies

For every file classified as "related":

1. Check its imports. If it imports an uncommitted file, that file MUST be
   included. Recurse.
2. Check for associated files:
   - New module → its tests?
   - New component → styles, config, registration?
   - Plan/doc changes related to the code change?
3. Search broadly: `git status -s | grep -i <feature-keyword>`
   If a scope hint was provided, use terms from the hint as keywords.
4. Check `.claude/logs/` — include session logs for this session.

**Common mistakes to avoid:**
- Committing `A.js` which imports `B.js` without committing `B.js` → 404
- Committing a module but not its tests
- Missing files from a prior compacted context (they show as `??`)

## Phase 4 — Stage & Review

1. **Check for pre-staged files** before adding anything:
   ```bash
   git diff --cached --stat
   ```
   If files are already staged that you didn't stage, another session left
   them in the index. **STOP and report** — do not commit on top of someone
   else's staged work. Past failure: commit `b69ec3f` swept in 146 lines of
   another session's codegen changes because they were pre-staged in the index.

2. Stage only the related files by name:
   ```bash
   git add file1 file2 ...
   ```
   **NEVER use `git add .` or `git add -A`** — these grab everything.

3. Review what's staged — **verify the count matches what you just added:**
   ```bash
   git diff --cached --stat
   ```
   If the file count is higher than the number of files you staged in step 2,
   something else was already in the index. Investigate before committing.

4. Present the staged file list to the user and confirm it looks correct.

## Phase 5 — Commit

1. Draft a commit message:
   - Summarize the nature of the change (feat, fix, refactor, docs, chore)
   - Focus on the **why**, not the **what**
   - 1-2 sentences, concise
   - Follow the style of recent commits (`git log --oneline -10`)
   - If a scope hint was provided, use it to inform the message (but don't
     just parrot it — write a proper commit message)

2. **Run tests if code was staged** — if any staged files are code (`.js`,
   `.css`, `.html`, `.rs`), run `npm run test:all` before committing. All
   suites must pass. If tests fail after two fix attempts on the same error,
   STOP and report to the user (CLAUDE.md: "NEVER thrash on a failing fix").
   Skip this step for content-only commits (`.md`, `.jpg`, `.png`, logs).

3. **Dispatch a fresh agent to review the staged changes before committing.**
   The agent receives `git diff --cached` and the proposed commit message.
   It checks:
   - Are all related files included? Any missing dependencies?
   - Are any unrelated files accidentally staged?
   - Does the commit message accurately describe the changes?
   - Any obvious issues in the diff (debug code, TODOs, broken imports)?

   Do NOT review the staged changes yourself — you selected the files, so
   you have selection bias. A fresh agent catches files you missed or
   included by mistake.

   **The reviewer is READ-ONLY.** Include this verbatim in the dispatch prompt:

   > You are read-only. Allowed: Read files, run read-only git (`diff`, `log`,
   > `show`, `show-ref`, `ls-files`, `ls-remote`, `status`), run existing
   > tests. FORBIDDEN: `git stash` (push/-u/save/bare), `checkout`, `restore`,
   > `reset`, `add`, `rm`, `commit`, editing files, creating worktrees. For
   > pre-fix behavior, use `git show <commit>:<file>` — don't modify reality.
   > (Past failure: reviewer ran `git stash -u && test && git stash pop`; the
   > pop silently unstaged the caller's staged files.)

   If the agent raises concerns: **STOP.** Report the concerns to the user.
   Do not commit until concerns are resolved.

   If the agent approves: proceed to step 4.

4. Commit using a HEREDOC for clean formatting:
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>: <message>

   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

5. Verify:
   ```bash
   git status -s
   ```

**If a pre-commit hook fails:** fix the issue, re-stage, and create a NEW
commit. NEVER use `--amend` after a hook failure — the commit didn't happen,
so amend would modify the PREVIOUS commit. Maximum 2 attempts on the same
hook error — if it fails twice, STOP and report.

## Phase 6 — Push (if `push` argument)

Only if `push` was in the arguments:

```bash
git push
```

If there's no upstream tracking branch:
```bash
git push -u origin <branch-name>
```

**NEVER force-push to main/master.** If push is rejected, tell the user why
and ask what to do.

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
    if timeout 600 gh pr checks "$PR_NUMBER" --watch 2>/dev/null; then
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

## Phase 7 — Land (if `land` argument)

Only if `land` was in the arguments.
This is for landing worktree work onto main via cherry-pick.

**Pre-checks:**
- Confirm we're in a worktree (not main). If on main, stop and explain.
- Ensure all worktree changes are committed first (run Phases 1-5 if needed).

**Steps:**

1. **Identify commits to land:**
   ```bash
   git log --oneline main..HEAD
   ```
   Present the list to the user for approval.

2. **Switch to main repo and inventory:**
   ```bash
   cd <main-repo-path>
   git status -s
   ```
   Do NOT stash — it can silently merge or lose other sessions' work. Let
   git's overlap detection handle it in step 3.

3. **Cherry-pick approved commits (try-without-stash):**
   ```bash
   git cherry-pick <commit-hash>
   ```
   One at a time. On any refusal or conflict: **STOP** and report to the
   user. Do not force-resolve, stash, or `--abort` without asking — the
   conflict state preserves evidence.

4. (No stash restore — we never stashed.)

5. **Run tests after cherry-picks land:**
   ```bash
   npm run test:all
   ```
   If tests fail, report to the user. Do NOT attempt to fix — the
   cherry-picked code was already tested in the worktree. A failure here
   means a main-specific conflict that needs human judgment.

6. **Write `.landed` marker** on the worktree (so `/fix-report` knows
   it's safe to remove):
   ```bash
   cat <<LANDED | bash scripts/write-landed.sh "<worktree-path>"
   status: full
   date: $(TZ=America/New_York date -Iseconds)
   source: commit-land
   commits: <list of cherry-picked hashes>
   LANDED
   ```

7. **Verify:**
   ```bash
   git status -s
   git log --oneline -5
   ```

## Key Rules

- **NEVER use `git add .` or `git add -A`** — stage files by name only.
- **NEVER touch unrelated changes** — other agents may have work in progress.
  Do not `git checkout --`, `git restore`, `git reset`, or otherwise discard
  changes you didn't make.
- **NEVER amend after hook failure** — create a new commit instead.
- **NEVER force-push to main/master** — warn and ask.
- **NEVER push without the `push` argument** — commit only by default.
- **Do NOT stash** — hook blocks `git stash push/-u/save/bare`. For
  cherry-pick flows, use the try-without-stash pattern (Phase 7 step 3).
- **If unsure whether a file is yours: ask.** The cost of asking is low. The
  cost of committing or discarding someone else's work is high.
- **Include `.claude/logs/`** — session logs should be committed alongside
  code changes.
- **Always use HEREDOC for commit messages** — ensures clean multi-line
  formatting.
- **Scope hint is advisory, not absolute** — even with a scope hint, check
  diffs. Some related files won't match the hint keywords, and some keyword
  matches may be unrelated. The hint narrows the search; it doesn't replace
  judgment.
- **`/commit pr` requires a clean working tree** — all changes must be
  committed before running PR mode. The pre-check enforces this.
- **`/commit pr` keyword is first-token-only** — prevents false-triggering
  on scope hints that contain "pr" mid-string.
- **PR body uses `git log origin/main..HEAD`** — not `git log main..HEAD`
  (local main may be stale after rebase).
- **PR number from URL, not bare `gh pr view`** — bare view uses ambient
  branch autodetect, which is subject to race conditions.
