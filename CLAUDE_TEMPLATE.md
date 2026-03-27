# {{PROJECT_NAME}} -- Agent Reference

## Architecture

{{SOURCE_LAYOUT}}

## Dev Server

```bash
{{DEV_SERVER_CMD}}
```

The port is determined automatically by `{{PORT_SCRIPT}}`: **8080** for the main repo (`{{MAIN_REPO_PATH}}`), a **deterministic unique port** for each worktree (derived from the project root path). Run `node {{PORT_SCRIPT}}` to see your port. Override with `DEV_PORT=NNNN` env var if needed.

**NEVER use `kill -9`, `killall`, `pkill`, or `fuser -k` to stop processes.** These can kill container-critical processes or disrupt other sessions' dev servers and E2E tests. If a port is busy, check what's on it with `lsof -i :<port>` and ask the user to stop it manually.

**Auth gate:** The app requires a password. For automated browser testing, bypass it:
```js
{{AUTH_BYPASS}}
```
Then reload the page.

## Tests

```bash
{{UNIT_TEST_CMD}}    # Unit tests only -- fast, use while working
{{FULL_TEST_CMD}}    # ALL suites -- use before committing
```

**`{{FULL_TEST_CMD}}` must pass before every commit.** When reporting test
results, always state the COMMAND you ran and list EACH suite with its result.
If a suite was skipped, say so explicitly with the reason.
Never say just "all tests pass" -- specify which suites actually ran and the
command that ran them.

**NEVER weaken tests to make them pass.** Do not loosen tolerances, widen mismatch thresholds, skip assertions, or remove test cases to avoid failures. When a test fails, always find the root cause. Fix the code that's broken -- not the test. Only alter a test if the test itself is genuinely wrong (e.g., testing the wrong expected value). Weakened tests will be caught in review and the change will be rejected.

**NEVER modify the working tree to check if a failure is pre-existing.** No `git stash && {{UNIT_TEST_CMD}} && git stash pop`, no `git checkout <old-commit>`, no temporary worktrees for comparison. These workflows are fragile -- context compaction between the modification and the restore will lose your changes. Past failure: an agent stashed changes, checked out a prior commit to verify a test failure was pre-existing, hit compaction, and never restored the working tree. If you touched code and tests fail, fix them. If you only touched content (markdown, images, etc.), don't run tests at all.

**NEVER thrash on a failing fix.** If you attempt a fix, run tests, and the same test fails again, STOP. Do not try a third approach to the same problem -- you are guessing and will keep guessing wrong. Report: (1) what you tried, (2) what failed both times, (3) why you think it's failing. Let the user decide the next step. This applies to all retry loops: fix+verify cycles, test failures after cherry-pick, and any "fix -> test -> still fails" pattern. Two attempts at the same error is the maximum.

**Capture test output to a file, never pipe.** Always run tests with:
`{{FULL_TEST_CMD}} > {{TEST_OUTPUT_FILE}} 2>&1` -- then read the file to
inspect failures. Never pipe through `| tail`, `| head`, `| grep` -- it
loses output and forces re-runs.

**Pre-existing test failures.** If a test fails in code you didn't touch,
verify with `git log` that the test/source predates your changes. You may
file a GitHub issue with the error output and mark the test `it.skip('name
// #NNN')`. Never skip tests you wrote or modified.

**NEVER defer the hard parts of a plan.** When implementing a plan, finish all of it -- do not split work into phases and then stop after the easy phase, reframing the remaining work as "next steps" or "future phases." If the plan says to do X, do X. Stopping partway and declaring victory on the easy part undermines progress and the entire project. If you genuinely cannot finish in one session, be explicit that the work is incomplete, not that it's a planned future phase.

**Optimize for correctness, not speed.** Follow instructions exactly, including every intermediate verification step. Never skip verification to "save time" -- skipped steps mean the user has to re-verify, which saves nothing. Never stub methods, return bogus values, or simplify implementations to get something working faster. Never reframe the task to make it easier. Review agents will find shortcuts, so cutting corners gains nothing. When the user says "after each step, verify" -- verify after each step, not once at the end.

### Test files

{{TEST_FILE_PATTERNS}}

## Playwright CLI (Browser Automation)

This environment uses `playwright-cli` for browser automation. Run `playwright-cli --help` for available commands.

### Screenshots

Use `playwright-cli screenshot` without `--filename` so files save to the configured output directory (`.playwright/output/`). Then rename the file to something descriptive. Using `--filename` bypasses the output directory and saves to the working directory instead.

### Manual Testing Philosophy

When told to "test manually", "test in the browser", or "verify with playwright-cli", use **real mouse/keyboard events** (`click`, `mousemove`, `mousedown`, `mouseup`, `type`, `press`, `drag`) -- never `page.evaluate()` or `eval` to call JS APIs that simulate user actions.

- **Real events only:** Use real mouse/keyboard interactions for all user-facing operations.
- **`eval`/JS is only for setup and assertions:** Auth bypass, reading state for verification, querying DOM attributes. Never for simulating clicks, drags, or keypresses.

## Worktree Rules

Worktrees (`isolation: "worktree"`) exist to keep agent work **isolated and reviewable**. Respect that isolation:

- **NEVER apply worktree changes to main without explicit user approval.** Do not `git apply`, `git merge`, copy files, or otherwise move worktree changes into the main working directory unless the user says to. This is the whole point of using worktrees.
- **NEVER remove worktrees that contain changes.** The user may want to review, cherry-pick, or discard them individually. Only clean up worktrees the user has approved or explicitly told you to remove.
- **Verify EACH worktree before removing.** Never batch-remove worktrees without checking each one. The fastest check: does `<worktree>/.landed` exist with `status: full`? If yes, it's safe -- all commits are on main and logs were extracted. If no `.landed` marker: verify manually with (1) `git log main..<branch>`, (2) `git status` in the worktree, (3) is it a long-running branch? Named/long-running worktrees are NOT sprint artifacts -- do not remove them. Present results and let the user approve.
- **ALWAYS write a `.landed` marker when worktree work is cherry-picked to main.** Without this marker, worktrees pile up because cleanup tools can't tell which are safe to remove. Write it immediately after successful cherry-pick:
  ```bash
  cat > "<worktree-path>/.landed" <<LANDED
  status: full
  date: $(TZ={{TIMEZONE}} date -Iseconds)
  source: <skill-name>
  commits: <list of cherry-picked hashes>
  LANDED
  ```
  If only some commits were cherry-picked (others skipped due to conflicts), use `status: partial`. If you used a worktree and finished without landing, still write a marker with `status: not-landed` so cleanup knows the agent is done.
- **After agents finish:** present a summary of what each worktree changed, then **ask** which ones the user wants merged. Let the user drive.
- **Keep worktree changes separate from main.** The main working directory may have its own uncommitted changes. Mixing agent patches in without asking makes clean commits harder and defeats the isolation benefit.

## Git Rules

**Do NOT push to remote unless explicitly told to.** Commit freely when asked, but never `git push` without the user saying "push", "push it", or similar. This applies even when the user says "commit and push" for one task -- it does not carry over to future tasks.

**NEVER revert, discard, or "clean up" changes you didn't make.** If you see uncommitted changes from other agents or sessions, leave them alone. Do not run `git checkout -- <file>`, `git restore`, or any other command that discards working tree changes unless the user explicitly asks you to. Unrelated changes in the working tree are not yours to touch -- ask the user what they want to do with them.

**Protect untracked files before git operations.** Before `git stash`, `git cherry-pick`, `git merge`, or any operation that modifies the working tree: (1) run `git status -s | grep '^??'` to inventory untracked files, (2) if any exist, use `git stash -u` (not `git stash`) or save them to a temp location first. Untracked files are not in git and cannot be recovered if lost.

**Never use `git checkout <commit> -- <file>` for investigation.** To view old file versions, use `git show <commit>:<file>` or `git diff <commit1> <commit2> -- <file>` -- these are read-only and don't modify the working tree. `git checkout <commit> -- <file>` silently overwrites working tree AND stages the change, which easily gets swept into the next commit.

**Never use `--no-verify` to bypass pre-commit hooks.** Hooks exist for safety -- fix the hook failure, don't bypass it.

### Constructing commits -- feature-complete, not session-based

A commit must include **all files the feature needs** and **no unrelated files**. Do NOT rely on memory of "what I changed this session" -- context compaction creates artificial session boundaries that split work on a single feature across multiple contexts.

**Mandatory process before staging:**

1. `git status -s` -- see ALL uncommitted changes
2. For every changed/untracked file, decide: related to this commit or not?
3. **Trace dependencies**: for every file being committed, check its imports. If it imports an uncommitted file, that file must be included. Recurse.
4. **Search broadly**: `git status -s | grep -i <keyword>` for the feature name. Check tests, plans, styles, examples -- not just `src/`.
5. Verify: `git diff --cached --stat` before committing. Review the list.

**Common mistakes to avoid:**
- Committing `A.js` which imports `B.js` without committing `B.js`
- Committing a module but not its tests, styles, or config changes
- Missing files that were added in a prior compacted session (they show as untracked `??`, easy to overlook)
- Including unrelated changes that happened to be in the working tree
- Staging/unstaging shuffles (`git reset`, `git stash`) to separate changes -- these risk losing work. **If a file has a mix of related and unrelated changes, warn the user and ask what to do** -- do not attempt to split it yourself

**Enumerate before guessing.** Before building test models, constructing
URLs, or creating files from scratch, check what already exists: `ls` the
directory, `grep` for the term, read the relevant file. Agents consistently
skip this step and guess instead of looking.
