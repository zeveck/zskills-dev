# {{PROJECT_NAME}} -- Agent Reference

## Architecture

{{SOURCE_LAYOUT}}

## Subagent Dispatch

**NEVER dispatch agents on Haiku.** Haiku produces over-literal pattern matches and misses framing -- it greps for an exact string, doesn't find it, and concludes "no bug" when the actual problem is the absence of a guardrail. It is consistently wrong on judgment-class tasks. We do not use Haiku anywhere, period.

When using the Agent tool:

- **Default: omit the `model` parameter** so the subagent inherits the parent's model (typically Opus). This is the safe default.
- **`subagent_type: "Explore"` pins its own model frontmatter to Haiku 4.5 in this environment.** Do NOT use `Explore` without explicitly passing `model: "opus"` (or whichever model the parent is currently using). Prefer `subagent_type: "general-purpose"` -- it inherits the parent model with no override needed.
- Treat any subagent type as Haiku-by-default until you have read its agent definition and confirmed otherwise. When in doubt, pass `model: "opus"` explicitly, or use `general-purpose`.
- **Sonnet** is acceptable only for rare simple+mechanical work (bulk renames, find-replace, format conversion). Never for analysis, review, verification, or judgment.

## Dev Server

Run `bash scripts/start-dev.sh` to start the dev server and `bash scripts/stop-dev.sh` to stop it. Both ship as failing stubs that the consumer customizes (see in-file comments for the contract). The pairing: `start-dev.sh` runs `{{DEV_SERVER_CMD}}` and writes each spawned child PID (one per line) to `var/dev.pid`; `stop-dev.sh` reads `var/dev.pid` and SIGTERMs each. `var/` is gitignored.

The port is determined automatically (8080 for the main repo `{{MAIN_REPO_PATH}}`; a deterministic per-worktree port otherwise). Run `bash .claude/skills/update-zskills/scripts/port.sh` to see your port. Override with `DEV_PORT=NNNN` env var, or with a `scripts/dev-port.sh` stub for project-wide custom logic (see `.claude/skills/update-zskills/references/stub-callouts.md`).

**NEVER use `kill -9`, `killall`, `pkill`, or `fuser -k` to stop processes.** These can kill container-critical processes or disrupt other sessions' dev servers and E2E tests. Do not reach for `lsof -ti :<port> | xargs kill` either — it's the same anti-pattern under a different spelling. If a port is busy from another session's process, check with `lsof -i :<port>` and ask the user to stop it manually.

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

**Capture test output to a file, never pipe.** Route test output OUT of
the working tree so it never shows up in `git status`. The canonical idiom
is:

```bash
TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
{{FULL_TEST_CMD}} > "$TEST_OUT/.test-results.txt" 2>&1
```

Then read `"$TEST_OUT/.test-results.txt"` to inspect failures. Never pipe
through `| tail`, `| head`, `| grep` -- it loses output and forces re-runs.

**Pre-existing test failures.** If a test fails in code you didn't touch,
verify with `git log` that the test/source predates your changes. You may
file a GitHub issue with the error output and mark the test `it.skip('name
// #NNN')`. Never skip tests you wrote or modified.

**NEVER defer the hard parts of a plan.** When implementing a plan, finish all of it -- do not split work into phases and then stop after the easy phase, reframing the remaining work as "next steps" or "future phases." If the plan says to do X, do X. Stopping partway and declaring victory on the easy part undermines progress and the entire project. If you genuinely cannot finish in one session, be explicit that the work is incomplete, not that it's a planned future phase.

**Optimize for correctness, not speed.** Follow instructions exactly, including every intermediate verification step. Never skip verification to "save time" -- skipped steps mean the user has to re-verify, which saves nothing. Never stub methods, return bogus values, or simplify implementations to get something working faster. Never reframe the task to make it easier. Review agents will find shortcuts, so cutting corners gains nothing. When the user says "after each step, verify" -- verify after each step, not once at the end.

### Test files

{{TEST_FILE_PATTERNS}}

## Skill-file hardcode discipline

Skill files (`skills/**/*.md`) are shared across every project that installs zskills. Hardcoding consumer-specific literals -- `npm run test:all`, `npm start`, `TZ=America/New_York`, `$TEST_OUT/.test-results.txt`, the canonical co-author trailer -- in a fenced bash block ships that consumer's choice to every downstream. The deny-list at `tests/test-skill-conformance.sh` (literal list in `tests/fixtures/forbidden-literals.txt`) blocks new occurrences at CI time, and `hooks/warn-config-drift.sh` emits a real-time WARN when an Edit/Write introduces one. Replace each hit with the resolved variable (`$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, `${TIMEZONE:-UTC}`, `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}`, `$COMMIT_CO_AUTHOR`) sourced via `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`.

For the rare case where the literal is genuinely correct -- a prohibition example ("**Never hardcode `npm run test:all`**"), a migration tool detecting the antipattern, or a report-template string the agent prints verbatim -- mark it with an inspectable allow-hardcoded comment on the line **immediately above** the fence-opener (case-sensitive lowercase prefix, ` reason:` delimiter so multi-token literals like `npm run test:all` work). See `references/canonical-config-prelude.md` for the full format spec.

Two worked examples:

- **Prohibition-by-name** (skill documents an antipattern in a fenced sample report):
  ```
  <!-- allow-hardcoded: TZ=America/New_York reason: prohibition-by-name in run-plan SKILL.md cron-confirm example -->
  ```bash
  # The agent confirms wall-clock with TZ=America/New_York date for ET output.
  ```
  ```

- **Migration-tool literal** (the deny-list test or warn-hook fixture itself contains the literal so it can detect the antipattern):
  ```
  <!-- allow-hardcoded: scripts/port.sh reason: migration-tool literal in update-zskills SKILL.md detects antipattern -->
  ```bash
  grep -rn 'scripts/port.sh' skills/  # detects callers that haven't migrated
  ```
  ```

For regex deny-list entries (lines starting with `re:` in the fixture), the marker names the pattern WITHOUT the `re:` prefix:

```
<!-- allow-hardcoded: \$TEST_OUT/\.test-results\.txt reason: migration-tool literal demonstrating the migrated form -->
```bash
echo "Captured to $TEST_OUT/.test-results.txt"
```
```

The marker must be in markdown prose (HTML comments aren't bash-valid inside fences). Markers stack: place multiple consecutive marker lines above one fence to exempt multiple distinct literals in that fence. Any non-blank, non-marker line resets the marker block.

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

**Do NOT commit or push unless explicitly told to.** Permission to commit or push applies to the scope in which it was given -- a single task, a skill invocation, or a specific set of changes. It does not carry over to future tasks. "Commit this" means commit that thing. "Commit freely" during a `/run-plan` invocation means within that run. Only an explicit, unprompted, standalone statement like "from now on, commit without asking" grants ongoing permission -- and even that only lasts for the session. Never `git push` without the user explicitly saying "push", "push it", or similar.

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

## Execution Modes

Three landing modes control how agent work reaches main:

| Mode | Keyword | How it works |
|------|---------|-------------|
| Cherry-pick | (default) | Work in auto-named worktree, cherry-pick to main |
| PR | `pr` | Work in named worktree, push branch, create PR |
| Direct | `direct` | Work directly on main, no landing step |

**Usage:** Append keyword to any execution skill:
- `/run-plan plans/X.md finish auto pr`
- `/fix-issues 10 pr`
- `/research-and-go Build an RPG. pr`
- `/quickfix Fix README typo` — low-ceremony PR for trivial changes (no worktree; picks up in-flight edits in main)
- `/do Add dark mode. pr`

After a PR merges on GitHub, run `/cleanup-merged` to catch your local clone up (checkout main, pull, delete merged feature branches). Safe to run anytime; bails on a dirty tree.

**Config default:** Set in `.claude/zskills-config.json`:

    {
      "execution": {
        "landing": "pr",
        "main_protected": true,
        "branch_prefix": "feat/"
      }
    }

When `main_protected: true`, agents cannot commit, cherry-pick, or push
to main. Use PR mode or feature branches.

**Agent model minimum:** When dispatching an Agent (subagent), always use Sonnet or higher. Never dispatch Haiku — even for "simple" tasks. The minimum model is configured at `agents.min_model` in `.claude/zskills-config.json` and enforced by the `block-agents.sh` hook at dispatch time.

## Tracking Enforcement

Tracking file enforcement is active when `.zskills/tracking/` exists and the session is associated with a pipeline (via `.zskills-tracked` file or transcript). Skills create tracking files during pipeline execution; hooks check them before allowing `git commit`, `git cherry-pick`, and `git push`. Pipeline scoping (suffix matching on pipeline ID) ensures one pipeline's markers don't block another. The orchestrator writes `.zskills-tracked` (single-line pipeline ID) in both the worktree and main repo roots before dispatching agents, and removes it after pipeline completion. The `.claude/skills/update-zskills/scripts/clear-tracking.sh` script lets the user manually clear stale tracking state -- agents are blocked from running it directly.
