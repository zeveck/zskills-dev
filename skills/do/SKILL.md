---
name: do
disable-model-invocation: true
argument-hint: "<description> [worktree] [push] [pr] [every SCHEDULE] [now] | stop [query] | next [query] | now [query]"
description: >-
  Lightweight task dispatcher for ad-hoc work: documentation, examples,
  refactoring, content updates. Supports scheduling with every/now/next/stop.
  Usage: /do <description> [worktree] [push] [pr] [every SCHEDULE] [now] | stop | next.
---

# /do \<description> [worktree] [push] [pr] [every SCHEDULE] | stop [query] | next [query] | now [query] — Lightweight Task Dispatcher

Execute small, ad-hoc tasks with structured research, verification, and
optional isolation or auto-push. Can be scheduled for recurring maintenance
tasks. For work that doesn't warrant the full ceremony of `/run-plan` (plan
phases) or `/fix-issues` (batch bug fixing).

**Ultrathink throughout.**

## When to Use `/do`

| Task | Use |
|------|-----|
| Documentation, examples, presentations, screenshots | `/do` |
| Small refactors, one-off fixes, content updates | `/do` |
| Adding a new block type | `/add-block` (10-step workflow) |
| Newsletter entry | `/do` or `/doc newsletter` |
| Batch bug fixing (N issues) | `/fix-issues N` |
| Executing a plan phase | `/run-plan` |
| Multi-file feature work with dependencies | `/run-plan` |

**Rule of thumb:** if the task needs a worktree, separate verification agent,
and a persistent report file, it's too big for `/do`. Use `/run-plan` instead.

## Arguments

```
/do <description> [worktree] [push] [pr] [every SCHEDULE] [now]
/do stop | next
```

- **description** (required) — what to do, in natural language
- **worktree** (optional) — isolate work in a named worktree at
  `/tmp/<project>-do-<slug>/` for riskier or larger tasks. Without this
  flag, work happens directly on main.
- **push** (optional) — auto-push to remote after verification passes.
  Upgrades verification to use a **separate verification agent** running
  `/verify-changes`. Push never happens without verification passing first.
- **pr** (optional) — work in a named worktree on a named branch, then
  push and create a PR to main. Dispatches an implementation agent to do
  the work, waits for completion, rebases onto latest main, pushes, creates
  PR, and polls CI (report only).
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior.
- **stop** — cancel `/do` cron(s). Bare `/do stop` → all crons.
  With query `/do stop Check docs` → targets matching cron.
- **next** — check next fire time. Bare → all. With query → targeted.

**Detection:** If `$ARGUMENTS` starts with a quoted string (`"..."`),
the quoted text is the description — skip meta-command detection entirely.
This lets users escape edge cases like `/do "Now fix the tooltip bug"`.

Otherwise, check the **first word** of `$ARGUMENTS`:
- `stop [query]` — meta-command: cancel crons. Bare → all. With query → targeted.
- `next [query]` — meta-command: show fire times. Bare → all. With query → targeted.
- `now [query]` — meta-command: trigger immediately. Bare → all/ask. With query → targeted.

If the first word is NOT a meta-command, it's a regular task. Parse
trailing flags from the END backward:
- `push` — recognized at the end
- `worktree` — recognized at the end
- `pr` — recognized at the end (use extended pattern with `.!?` punctuation, since
  task descriptions are prose-like and "pr" may appear as "PR." at end of sentence)
- `every <schedule>` — recognized at the end (e.g., `every 4h`, `every day at 9am`)
- `now` — recognized at the end (only meaningful with `every`: run now AND schedule)

**PR flag detection pattern** (use extended `.!?` punctuation):
```bash
LANDING_MODE="default"
if [[ "$REMAINING" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then
  LANDING_MODE="pr"
fi
```

Everything before the trailing flags is the task description.

This means:
- `/do stop` — stop all `/do` crons
- `/do stop Check docs` — stop the "Check docs" cron
- `/do next` — show all fire times
- `/do next Check docs` — show fire time for "Check docs"
- `/do now` — trigger (if one) or ask (if multiple)
- `/do now Check docs` — trigger the "Check docs" cron
- `/do Push the latest changes` — description only, no flags
- `/do Update the presentation push` — description + push flag
- `/do Fix the tooltip bug worktree push` — description + both flags
- `/do Check docs every day at 9am` — schedule "Check docs" daily
- `/do Add dark mode. pr` — description + pr flag (PR mode)

Examples:
- `/do Add example models for Integrator and Derivative blocks`
- `/do Sort the screenshots in session-sequence-snapshots`
- `/do Refactor color constants in main.css worktree`
- `/do Update the presentation with Phase 3 results push`
- `/do Make sure docs are up to date every day at 9am`
- `/do Check for broken links in examples every 12h now`
- `/do Add dark mode to editor pr`
- `/do next` — all scheduled tasks
- `/do next Check docs` — specific task
- `/do stop` — cancel all
- `/do stop Check docs` — cancel specific task

## Meta-Commands: stop / next / now

These commands query or control `/do` crons. They work in two modes:

- **Bare** (`/do stop`, `/do next`, `/do now`) — applies to ALL `/do` crons
- **Targeted** (`/do stop Check docs`, `/do next Check docs`) — applies to the matching cron

### Cron Matching (for targeted commands)

When a description is present with `stop`/`next`/`now`, find the matching
cron by comparing the description against all `/do` cron prompts:

1. `CronList` → find all whose prompt starts with `Run /do`
2. Extract each cron's task description (strip `Run /do ` prefix and
   trailing flags)
3. **Fuzzy match:** check if the user's description words appear in the
   cron's description (case-insensitive, order-independent). E.g.,
   "Check docs" matches "Make sure docs are up to date" because both
   key words overlap. The user won't have tons of similar `/do` crons,
   so loose matching is fine.
4. **One match** → act on it. **Multiple matches** → list them, ask
   which one. **No matches** → report "no matching /do cron found."

### Now

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **One cron:** extract prompt, **run immediately.** Cron stays active.
3. **Multiple (bare only):** list them, ask which to trigger.
4. **None:** report `No active /do cron to trigger.` and **exit.**

### Next

1. `CronList` → find `/do` crons (all, or matching if description given)
2. For each, parse the cron expression and compute the next fire time.
   Use `TZ=America/New_York date` for the timezone. Show both relative
   and absolute:
   > Active /do crons:
   > 1. ~14h 47m (~9:03 AM ET tomorrow, cron XXXX)
   >    Prompt: Run /do Make sure docs are up to date every day at 9am now
   > 2. ~3h 12m (~8:15 PM ET, cron YYYY)
   >    Prompt: Run /do Check broken links every 4h now
3. **None:** `No active /do cron in this session.`
4. **Exit.**

### Stop

1. `CronList` → find `/do` crons (all, or matching if description given)
2. **Bare with one cron:** delete it. Report what was cancelled.
3. **Bare with multiple:** list them, ask which to cancel (or "all").
4. **Targeted:** delete the matched cron. Report what was cancelled.
5. **None:** report "no active /do cron found."
6. **Exit.**

## Phase 0 — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression.

   **For interval-based schedules** (`4h`, `12h`): use the CURRENT minute
   as the offset so the first fire is a full interval from now. Check with
   `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *`

   **For time-of-day schedules**: offset round minutes by a few:
   - `day at 9am` → `3 9 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — `CronList` and check for existing `/do` crons.
   Extract the task description from each cron's prompt by stripping
   `Run /do ` prefix and trailing flags (`every`, `now`, `worktree`, `push`).
   - If an existing cron's extracted description **exactly matches** (case-
     insensitive) the new task's description, replace it (`CronDelete` +
     recreate). This is a re-registration of the same task.
   - Otherwise, keep it — the user has multiple crons for different tasks.
   - During an **unattended cron fire** (the invocation itself came from a
     cron), never ask the user — default to keeping both. During an
     **interactive invocation**, if descriptions are similar but not exact,
     list existing crons and ask: "Replace this one, or keep both?"

3. **Construct the cron prompt.** Always include `now` in the cron prompt
   so each cron fire runs immediately AND re-registers itself. Note: this
   `now` is for the CRON's invocation, not the current invocation:
   ```
   Run /do <description> [worktree] [push] every <schedule> now
   ```

4. **Create the cron** — `CronCreate` with `recurring: true`.

5. **Confirm** with wall-clock time.

6. **If `now` is present:** proceed to Phase 1.
   **If `now` is NOT present:** **Exit.** The cron fires later.

If `every` is NOT present, skip this phase (bare invocation runs immediately).

## Phase 1 — Understand & Research

Before touching anything:

1. **Parse the task description** — what is being asked? What files are
   involved? What's the expected outcome?

2. **Identify relevant files and current state:**
   - Search for files related to the task (Glob, Grep)
   - Read existing content that will be modified
   - Check for related skills, conventions, or guidelines (e.g., model
     design rules for example models, newsletter format for entries)

3. **Classify the change type** — this determines verification intensity
   in Phase 3:
   - **Content only** — markdown, images, presentations, documentation.
     No tests needed.
   - **Code** — JavaScript, CSS, HTML, model files. Tests needed.
   - **Mixed** — both content and code. Tests needed for code portion.

4. **Plan the work** — no formal document, just mental clarity on what
   to do and in what order. If the task is bigger than expected (would
   take 1000+ lines of changes, has complex dependencies), suggest
   `/run-plan` instead and ask the user.

## Phase 1.5 — Argument Parsing (always before Phase 1 research)

Before any research or execution, parse flags from `$ARGUMENTS`.

**Step 1: Check for `pr` flag** (trailing, using extended punctuation pattern):
```bash
REMAINING="$ARGUMENTS"
LANDING_MODE="default"
if [[ "$REMAINING" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then
  LANDING_MODE="pr"
  # Strip the pr token from description
  TASK_DESCRIPTION=$(echo "$REMAINING" | sed -E 's/(^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?])/ /')
  TASK_DESCRIPTION=$(echo "$TASK_DESCRIPTION" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
  if [ -z "$TASK_DESCRIPTION" ]; then
    echo "ERROR: Task description required. Usage: /do <task description> pr"
    exit 1
  fi
fi
```

If `LANDING_MODE` is not `pr`, then `TASK_DESCRIPTION` is the full `$ARGUMENTS` minus the other trailing flags (`push`, `worktree`, `every ...`, `now`).

**Step 2: Check for `worktree` flag** (trailing, plain word match):
```bash
if [[ "$REMAINING" =~ (^|[[:space:]])worktree($|[[:space:]]) ]]; then
  USE_WORKTREE=true
fi
```

**Step 3: Check for `push` flag** (trailing):
```bash
if [[ "$REMAINING" =~ (^|[[:space:]])push($|[[:space:]]) ]]; then
  USE_PUSH=true
fi
```

`pr` takes precedence: if `LANDING_MODE="pr"`, ignore `worktree` and `push` flags.

## Phase 2 — Execute

Choose execution path based on parsed flags:

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
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \
  || git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
```

**Step A5 — Write tracking marker immediately after worktree creation:**
```bash
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
    if timeout 600 gh pr checks "$PR_NUMBER" --watch 2>/dev/null; then
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
# default to OPEN to keep the flow going AND warn so the failure is visible.
if ! PR_STATE=$(gh pr view "$PR_URL" --json state --jq '.state' 2>/dev/null); then
  echo "WARNING: gh pr view failed for $PR_URL — defaulting pr_state to OPEN (may be stale; verify at PR URL)" >&2
  PR_STATE="OPEN"
fi
if [ "$PR_STATE" = "MERGED" ]; then
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

### Path B: Worktree mode (`worktree` flag, no `pr`)

Create a named worktree at `../do-<slug>/` using manual `git worktree add`:

```bash
# Compute slug from task description
WORD_COUNT=$(echo "$TASK_DESCRIPTION" | wc -w)
N=$(( WORD_COUNT < 4 ? WORD_COUNT : 4 ))
TASK_SLUG=$(echo "$TASK_DESCRIPTION" | awk "{for(i=1;i<=$N;i++) printf \$i\"-\"; print \"\"}" \
  | sed -E 's/[^a-zA-Z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//' \
  | tr '[:upper:]' '[:lower:]' \
  | cut -c1-30 \
  | sed 's/-$//')
WORKTREE_PATH="../do-${TASK_SLUG}"
# Collision check
if [ -d "$WORKTREE_PATH" ]; then
  TASK_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
  WORKTREE_PATH="../do-${TASK_SLUG}"
fi
git worktree add "$WORKTREE_PATH"
```

Do the work inside the worktree. The verification agent commits after tests pass (one logical unit per commit).

### Path C: Direct (default, no `pr`, no `worktree`)

Work directly on main.

**Follow existing conventions in all paths:**
- Example models → `/model-design` skill guidelines
- Newsletter entries → existing NEWSLETTER.md format
- Documentation → existing doc style in the repo
- Code → existing patterns in the codebase

**Commit discipline (Paths B and C):**
- **On main (Path C):** commit when the work is complete. Clean, descriptive
  message. `npm run test:all` before committing if code was touched.
  If tests fail after two fix attempts on the same error, STOP — report
  what you tried and let the user decide.
- **In worktree (Path B):** the verification agent commits after tests pass.
  One logical unit per commit.

## Phase 3 — Verify

Verification intensity matches the change type (from Phase 1):

### Content-only changes (md, jpg, png, presentations)

- **Spot-check:** formatting, links, file organization, image references
- **Do NOT run tests** — running 4,000+ tests for a markdown edit is
  wasteful, and pre-existing failures would block the task unnecessarily
- **If `push` is present:** dispatch a separate verification agent. Tell
  the agent explicitly: "These are content-only changes (no code). Review
  the diff for correctness and completeness — do NOT run `npm test` or
  `npm run test:all`. Your job is: do these changes make sense? Are the
  right files included? Anything accidentally staged? Formatting correct?"
  Do NOT invoke `/verify-changes` for content-only pushes — it will run
  the full test suite regardless. Instead, dispatch a plain review agent.

### Code changes (js, css, html)

- **Run `npm run test:all`** — all suites must pass, not just unit tests.
- **If tests fail: fix them.** Do not check if failures are pre-existing.
  Do not stash, checkout old commits, or create comparison worktrees.
  If you touched code and tests fail, they're yours to fix. (See
  CLAUDE.md: "NEVER modify the working tree to check if a failure is
  pre-existing.")
- **If `push` is present:** dispatch a **separate verification agent**
  running `/verify-changes`. This is the full 7-phase verification:
  diff review, test coverage audit, `npm run test:all`, manual
  verification if UI, fix problems, re-verify until clean. Push only
  happens if this agent reports clean.

### Mixed changes

- Run tests for the code portion
- Spot-check the content portion
- If `push`: full `/verify-changes` via separate agent

## Phase 4 — Push (if `push` flag present, Path C/B only)

Only reached if Phase 3 verification passed. Not applicable to PR mode (Path A — PR mode has its own push in Phase 2 Step A7).

1. **If on main (Path C):**
   ```bash
   git push
   ```

2. **If in worktree (Path B):** cherry-pick to main first, then push:
   - Protect uncommitted work on main (`git stash -u` if needed)
   - Cherry-pick worktree commits to main sequentially
   - If any cherry-pick conflicts: **abort and clean up:**
     ```bash
     git cherry-pick --abort
     ```
     Restore stash if one was created (`git stash pop`). If `/do` has an
     active cron, kill it (`CronList` + `CronDelete` any whose prompt
     starts with `Run /do`). Report the conflict to the user. Do NOT
     force-push or resolve automatically.
   - Restore stash if one was created
   - Push main
   - Report what was pushed (commit hashes, branch)

3. **If verification failed:** do NOT push. Report the verification
   findings and stop.

## Phase 5 — Report

Brief inline output. No persistent report file.

**On main (no worktree, no push):**
```
Done. [1-2 sentence summary of what was done]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
```

**On main with push:**
```
Done and pushed. [1-2 sentence summary]
Changed: file1.js, file2.md (+N lines)
Committed: abc1234 — "commit message"
Pushed to: origin/main
Verification: clean (npm run test:all passed, /verify-changes clean)
```

**In worktree (no push):**
```
Done. [1-2 sentence summary]
Worktree: ../do-<slug>/
Branch: do/<slug>
Commits: abc1234, def5678
To land: git cherry-pick abc1234 def5678
To discard: git worktree remove ../do-<slug>/
```

**In worktree with push:**
```
Done and pushed. [1-2 sentence summary]
Cherry-picked to main: abc1234, def5678
Pushed to: origin/main
Verification: clean (/verify-changes clean)
Worktree: ../do-<slug>/ (can be removed)
```

**PR mode (pr flag):**
```
Done. [1-2 sentence summary of what was implemented]
PR: <PR_URL>
Branch: <BRANCH_NAME>
Worktree: <WORKTREE_PATH>
CI: passed | failed | no checks
Status: pr-ready | pr-ci-failing | landed
```

## Error Handling

- **Test failures (code changes):** stop, fix the code, re-test. Never
  weaken tests. Never check if failures are pre-existing.
- **Content issues:** stop, fix formatting/links/references, re-check.
- **Cherry-pick conflict (worktree + push):** stop, report the conflict.
  Do not resolve automatically — conflicts need human judgment.
- **Push failure (auth, remote, etc.):** stop, report the error.
- **Task is bigger than expected:** stop, suggest `/run-plan` instead.
  Ask the user before continuing.
- **PR mode: rebase conflict:** write `.landed` with `status: conflict`,
  report to user, direct them to inspect `$WORKTREE_PATH`.
- **PR mode: CI failure:** write `.landed` with `status: pr-ci-failing`,
  report the failure. Do NOT dispatch fix agents.
- **PR mode: implementation agent fails without committing:** write
  `.landed` with `status: conflict` and exit with an error message.
- **If stuck on anything:** report the state and ask the user for
  guidance. Do not retry the same approach in a loop.

## Key Rules

- **Match verification to change type** — content-only tasks skip tests.
  Code tasks run tests. Push upgrades to full `/verify-changes`.
- **Never weaken tests** — fix the code, not the test.
- **Never modify the working tree to check pre-existing failures** — if
  you touched code and tests fail, fix them. No stash-and-compare, no
  checkout-old-commit, no comparison worktrees.
- **Protect other agents' work** — do not commit unrelated changes that
  happen to be in the working tree. Stage only files related to the task.
- **Worktree naming (worktree flag)** — use `../do-<slug>/` where `<slug>`
  is a short kebab-case description derived from the task (e.g.,
  `do-sort-screenshots`, `do-integrator-examples`). Include a timestamp
  suffix if a worktree with that name already exists. Uses manual
  `git worktree add` — NOT `isolation: "worktree"`.
- **Worktree naming (pr flag)** — use `/tmp/<project>-do-<slug>/` with
  a named branch `<branch_prefix>do-<slug>`. Both BRANCH_NAME and
  WORKTREE_PATH derive from TASK_SLUG (after any collision suffix).
- **No persistent report files** — `/do` outputs results inline. It does
  NOT write SPRINT_REPORT.md, PLAN_REPORT.md, or any other report file.
  The commit is the artifact.
- **Push requires verification** — `push` always dispatches a separate
  verification agent before pushing. No exceptions.
- **PR mode CI is report-only** — `/do pr` polls CI and reports status.
  It does NOT dispatch fix agents. For automated fix cycles, use
  `/run-plan` or `/fix-issues` in PR mode.
- **PR body uses `git log origin/main..HEAD`** — never `git log main..HEAD`
  (local main may be stale after rebase).
- **PR titles and bodies are explicit** — never use `--fill` in `gh pr create`.
- **Slug collision suffix targets TASK_SLUG itself** — not just WORKTREE_PATH.
  Both BRANCH_NAME and WORKTREE_PATH must pick up the suffix.
- **Respect CLAUDE.md** — all standard rules apply (no external deps, no
  bundlers, no weakened tests, etc.)
