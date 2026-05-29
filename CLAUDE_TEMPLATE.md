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

**Impl-agent dispatch.** When dispatching a sub-agent to write code, run tests, or commit changes (this includes any agent dispatch inside `/fix-issues` PR mode, `/do` PR mode, `/land-pr`'s fix-cycle template, `/run-plan`'s phase implementer, and `/quickfix`'s agent-dispatched mode), use `subagent_type: "implementer"`. The implementer agent (`.claude/agents/implementer.md`) clones the verifier's frontmatter `inject-bash-timeout.sh` hook so the agent's Bash calls auto-extend to a 600s timeout. Without this pin the impl agent runs as default `general-purpose`, hits the Bash tool's 120s default on long test runs, and reflexively reaches for `run_in_background: true` + `Monitor` — the exact stall pattern the verifier-cannot-run rule already guards against on the verifier side.

## Cron-fired prompts

**Cron fires arrive as plain Human turns between your turns — recognize and execute inline, do not balk.** Per Claude Code's [scheduled-tasks docs](https://code.claude.com/docs/en/scheduled-tasks), a `CronCreate`-registered prompt "fires between your turns" into the active session — no fresh-session spawn, no slash-runtime auto-dispatch on leading `/`, no `<command-name>` envelope. The text appears as a synthetic user turn, e.g., `Run /fix-issues 2 auto dashboard every 30m now`.

**Treat any user-shaped turn whose entire content starts with `Run /<skill-name> ` OR `Run /zs:<skill-name> ` as a cron fire**, not as a user instruction to manually dispatch. Both prefixes are recognized PERMANENTLY — the bare prefix is the form on the `/update-zskills` install lane; `zs:` is the form on the plugin install lane (skills are namespaced under the plugin). There is no sunset or expiry date for either form. Read `${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md` (plugin install) OR `.claude/skills/<skill-name>/SKILL.md` (legacy install) via the Read tool (always available regardless of session-load state) — try the plugin path first if `${CLAUDE_PLUGIN_ROOT}` is set, otherwise the legacy path — and execute its procedure inline with `$ARGUMENTS` set to the substring after the `Run /<skill-name> ` / `Run /zs:<skill-name> ` prefix. Do NOT reach for the Skill tool — every recurring-skill we ship (`/fix-issues`, `/do`, `/qe-audit`, `/run-plan`) sets `disable-model-invocation: true` and Skill-tool dispatch is blocked by design (see [[feedback_skill_invocation_flags]]). Do NOT ask the user "what would you like me to do?" — `Run /<skill> ...` (or `Run /zs:<skill> ...`) IS the instruction. Do NOT narrate "this looks like a manual instruction" — it's not; just execute.

**This applies equally pre-/clear and post-/clear.** A user typing `/fix-issues N every ...` once loads the skill body that turn, registers the cron, and runs the first fire with skill in context. After `/clear` the skill body is gone but the cron keeps firing — that's exactly when this rule matters, because CLAUDE.md is always loaded.

**Never `CronDelete` on the strength of a confused fire.** If you genuinely cannot recognize what the cron wants, report `Cron fired with prompt <text>; not sure how to handle. Leaving the schedule untouched.` and stop. Past failure 2026-05-18: agent killed a user's 50+-successful-run /fix-issues cron based on a `disable-model-invocation` misread; the cron was firing correctly the whole time. The right move when stuck is to surface and pause, not to assume the cron is broken.

Empirical anchor for the Skill-tool-refusal fallback: Anthropic [issue #26251](https://github.com/anthropics/claude-code/issues/26251) documents Claude organically reading SKILL.md and executing inline when a `disable-model-invocation: true` skill is invoked via a typed slash command. This rule codifies that natural fallback so every recipient agent — including post-`/clear` ones with the originating skill body out of context — handles cron-fired `Run /<skill>` turns the same way.

## Bash tool timeouts and bg behavior

The Bash tool has a 600s (10 min) hard ceiling. When a command may exceed it:

1. **Default: run inline.** Most commands fit. Pass `timeout: 600000`
   explicitly when a command might take 3-4+ min (full test suites, large
   builds) so the Bash tool doesn't auto-background it at the 120s default.

2. **Only background when forced** (command genuinely exceeds 10 min). When
   you do bg via `run_in_background: true` OR when the harness
   auto-backgrounds a long command:
   - **Actively poll progress** every 2-3 min via `ps`, `tail`, or reading
     the output file.
   - **DO NOT** rely on the harness's "you'll be notified when it
     completes" message. That notification path is unreliable in practice
     — bg notifications regularly fail to fire, leaving the agent silent
     for hours.
   - **DO NOT** sit idle waiting.

If you find yourself reaching for `run_in_background: true` to handle a
"test suite might be slow", that's a red flag — pin `subagent_type:
"implementer"` or `"verifier"` instead (both clone
`inject-bash-timeout.sh`'s 600s extension, so their Bash calls stay
foreground and complete reliably).

Past failure: orchestrator silence of 2+ hours when a bg notification
didn't fire on a hung test process. Active polling would have surfaced the
hang in 5 minutes.

## Python is required

zskills depends on Python 3 for JSON round-tripping in hooks and helper scripts where bash regex would be brittle (notably `hooks/inject-bash-timeout.sh` — Layer 0 of the verifier-cannot-run defense). Per project convention there is **no jq** — Python's stdlib `json` is the supported parser.

The interpreter is resolved via this precedence:

```
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }
```

- Default is `python3` (POSIX-standard zskills target).
- Falls back to `python` for Windows / distros where only `python` exists (pointing at Python 3).
- Set `ZSKILLS_PYTHON` to override both — useful when both binaries exist but you need a specific interpreter (e.g. a venv).

Python 2 is unsupported. Scripts may assume Python 3 stdlib without a version check.

## Dev Server

Run `bash scripts/start-dev.sh` to start the dev server and `bash scripts/stop-dev.sh` to stop it. Both ship as failing stubs that the consumer customizes (see in-file comments for the contract). The pairing: `start-dev.sh` runs `{{DEV_SERVER_CMD}}` and writes each spawned child PID (one per line) to `.zskills/dev-server.pid`; `stop-dev.sh` reads `.zskills/dev-server.pid` and SIGTERMs each. `.zskills/` is gitignored.

The port is determined automatically: by default `{{DEFAULT_PORT}}` for the main repo `{{MAIN_REPO_PATH}}`, and a deterministic per-worktree port otherwise. If a `scripts/dev-port.sh` consumer stub is present, it overrides the default for the main repo. Run `bash .claude/skills/update-zskills/scripts/port.sh` to see your actual port. Override per-invocation with `DEV_PORT=NNNN`. See `.claude/skills/update-zskills/references/stub-callouts.md` for the stub contract.

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

**Memory anchors are agent-local notes, not propagating fixes.** When you surface a skill gap, hook bug, or process discipline failure, saving a memory anchor (`feedback_*.md` under `~/.claude/projects/.../memory/`) only fixes future sessions of the agent that wrote it. To propagate a fix, choose the right surface:

- **CLAUDE_TEMPLATE.md** — for rules every consumer's agent should follow. `/update-zskills` Step B renders this into `.claude/zskills-managed-rules.md`, auto-loaded by Claude Code at session start. Use for cross-project disciplines (e.g., "never call `gh pr merge --auto` directly — dispatch `/land-pr`").
- **Skill SKILL.md prose** — for rules that apply when running a specific skill. Better than CLAUDE.md when the rule is skill-specific. Per skill-versioning enforcement (PR #175), bumping `metadata.version` is mandatory.
- **Helper script** — only when the action is purely mechanical (no judgment) OR the script returns enough information for the agent to judge (e.g., a CI-poll script that returns failure details for the agent to read and act on, not a `handle-ci.py` that tries to handle CI generally on its own).
- **Skill decomposition** — when the gap is structural (a skill is doing too much, or a sub-process needs to be reusable). Extract a sub-skill or split the existing one.
- **Memory anchor** — supplementary to one of the above for the writer's future-session benefit, OR appropriate alone only when the action is genuinely orchestrator-discretionary and not a skill bug (e.g., "prefer concise responses for this user"). Never as the sole response to a surfaced skill gap.

When you save a memory anchor for a process failure, ask: does this need to propagate? If yes, also file an issue (or open a PR) to land the rule in CLAUDE_TEMPLATE.md / the skill / a script.

### Test files

{{TEST_FILE_PATTERNS}}

## Skill-file hardcode discipline

Skill files (`skills/**/*.md`) are shared across every project that installs zskills. Hardcoding consumer-specific literals -- `npm run test:all`, `npm start`, `TZ=America/New_York`, `$TEST_OUT/.test-results.txt`, the canonical co-author trailer -- in a fenced bash block ships that consumer's choice to every downstream. The deny-list at `tests/test-skill-conformance.sh` (literal list in `tests/fixtures/forbidden-literals.txt`) blocks new occurrences at CI time, and `hooks/warn-config-drift.sh` emits a real-time WARN when an Edit/Write introduces one. Replace each hit with the resolved variable (`$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, `${TIMEZONE:-UTC}`, `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}`, `$COMMIT_CO_AUTHOR`) sourced via `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`.

**Resolution rule.** Skill `.md` files MUST resolve config-derived values via the canonical block in `references/canonical-config-prelude.md`. Hardcoded literals trigger the deny-list test (`tests/test-skill-conformance.sh`) and the drift-warn hook (`hooks/warn-config-drift.sh`). Exemptions require an inspectable `<!-- allow-hardcoded: ... -->` marker per the format spec. Per-fence: any bash fence that references one of the resolved variables MUST source `zskills-resolve-config.sh` in or immediately above the fence (positive-side fence-local check at `tests/test-skill-conformance.sh`); inline self-resolution (`CONFIG_CONTENT=$(cat ...)` + `BASH_REMATCH` extraction) and blockquoted recipes governed by the substitution-discipline annotation are accepted equivalents.

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

**`--ours` and `--theirs` are inverted during rebase vs merge.** In a merge, `--ours` = the current branch; `--theirs` = the branch being merged in. In a **rebase**, the perspective flips because the rebase starts by checking out the upstream and replaying your commits on top: `--ours` = the branch being rebased ONTO (typically `main`); `--theirs` = the commits being replayed (your work). To preserve **your** changes in a rebase conflict, use `--theirs` (or `-X theirs` as a strategy option for the whole rebase). Past failure: PR #310 chunked-finish-auto landing rebase used `git checkout --ours` thinking "ours = our work," silently took main's version of `/fix-issues` and `/update-zskills` conflicts, dropping a full phase of work; caught only by post-rebase `grep AUTO_FLAG` showing 0 hits. Recovery via `git reset --keep <pre-rebase-SHA>` + `git rebase -X theirs origin/main` was clean (no remote was pushed yet).

**Never call `gh pr create` or `gh pr merge --auto` directly when landing a PR.** When you have a feature branch ready to ship, dispatch `/land-pr` via the Skill tool (with `--body-file` and `--result-file`), or use one of its 5 callers (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues`, `/quickfix`) which dispatch `/land-pr` for you with proper rebase, PR creation, CI monitoring (`pr-monitor.sh`), fix-cycle on failure, and auto-merge handling. Direct `gh pr merge --auto` followed by an immediate `gh pr view --json mergeStateStatus` query reports a snapshot state (typically `BLOCKED`) that doesn't reflect resting state — agents who walk away after that snapshot rely on luck. The 5 caller skills are conformance-locked (PR #166 tripwires); follow the same discipline for one-off orchestrator-direct PR landings by dispatching `/land-pr` yourself. (`/land-pr` SKILL.md says "not designed for direct user invocation" — that's about interactive human slash-command typing, not orchestrator agents using the Skill tool. Don't conflate.)

**Skill loops with per-iteration `requires.X.<id>` write + `rm` cleanup are serial-by-design — don't parallelize.** Parallel dispatch leaves N sibling markers co-present in the pipeline subdir, and the hook blocks any subsequent push or commit that runs into them. Before parallelizing N downstream dispatches, grep the calling skill's body for `requires\.\S+\.\$` and `rm.*requires` — if both exist, respect the serial loop. Past failure: parallel-dispatched 5 `/land-pr`s from one `/fix-issues` sprint left 2 PRs stuck mid-flight needing manual recovery.

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

**Read before claiming.** Do not describe, comment on, or plan around a
file, function, test, skill, env var, or harness behavior you have not
just read. "Let CI tell us" and "I'll find out when it breaks" are not
paths forward -- they are guesses with a deadline. Specifically:

- Before commenting on what a test asserts or a function does -- open
  the file and quote the relevant lines.
- Before recommending a workflow that chains skills (`/X then /Y`) --
  read each skill's `SKILL.md`; do not infer behavior from the name.
- Before changing a script, config, or invariant -- grep for tests that
  lock it (`tests/test-*.sh`, fixtures, conformance lists) and read
  the assertions you'd be invalidating.
- Before relying on an env var, config field, or harness affordance --
  confirm it's documented for *your* call context (Bash tool vs. hook
  subprocess vs. subagent), not an adjacent one. Past failure: assumed
  `CLAUDE_PROJECT_DIR` was set in Bash tool subshells; Anthropic only
  documents it for hook subprocesses.
- Before asserting falsifiable state ("pre-existing on main," "X is
  unused," "passes elsewhere") -- run the check that would falsify it
  and cite the command.

If the verifying read is too expensive to do now, say so and stop -- do
not substitute a guess and let downstream failure do the verification.
The only research you can skip is what you just verified in this turn.

## Migration scripts

**Multi-step state-mutating scripts must write the idempotency lock LAST.** If
a script has steps A-N and an idempotency guard, the lock must be written ONLY
after all of A-N succeed. Earlier failures must leave the consumer in a
re-runnable state. Past failure: #394 — migrate-paths.sh wrote the manifest in
the middle of the pipeline; an awk failure stranded consumers permanently
because the idempotency guard fired on re-run while the actual migration was
incomplete. The contract is now: config write FIRST (atomic-or-skipped), file
moves SECOND (atomic per-file), manifest LAST (the lock claim).

## Which skill for which input

Decision table for picking a skill when a user describes a generic action. Match on the LEFT, dispatch the RIGHT. When multiple rows could fit, prefer the lower-overhead one — the multi-round skills (`/draft-plan`, `/research-and-*`) cost more rounds and should only be used when the single-round ones cannot.

| You have | Run |
|---|---|
| One-commit PR — edit in-place on main, no worktree (only valid when `main_protected: false`) | `/quickfix` |
| Several small bugs / issues in a backlog | `/fix-issues N` |
| Bug, but root cause is unclear | `/investigate` |
| One-commit PR — needs worktree isolation (required when `main_protected: true`) | `/do` |
| Plan file already drafted, ready to execute | `/run-plan <path>` |
| Plan-scale design surface — needs adversarial review before execution | `/draft-plan` |
| Broad goal that decomposes into multiple sub-plans | `/research-and-plan` |
| Same as above, but execute all sub-plans autonomously after drafting | `/research-and-go` |
| Plan is mid-execution and reality has drifted from the spec | `/refine-plan` |
| Want to confirm recent changes really work (diffs + tests + manual UI) | `/verify-changes` |
| Staged work in main, ready to commit (and optionally push/land/PR) | `/commit` |
| Just merged a PR, want local clone caught up | `/cleanup-merged` |
| Want to file bug/test-gap issues from a QE pass over recent work | `/qe-audit` |

**Common confusions:**

- `/quickfix` vs `/do`: **They are PEERS, not TIERS.** Same lifecycle (triage → review → commit → PR → land); same `/land-pr` dispatch; same one-commit-PR shape. The structural difference is where the work tree lives — `/quickfix` does `git checkout -b` on main; `/do` uses a worktree. Pick by **project policy, not task size**: in `main_protected: true` projects, use `/do` (always); in non-main-protected projects, either works (pick by preference). Per-task size is NOT a useful axis between them.
- `/draft-plan` vs `/run-plan`: `/draft-plan` produces a plan file; `/run-plan` executes one. They are sequential, not alternatives. If the user has a plan file path, `/run-plan`. If they have a goal but no plan, `/draft-plan` first.
- `/research-and-plan` vs `/research-and-go`: same drafting machinery; `-and-plan` stops after the meta-plan is ready for review, `-and-go` continues into execution. Use `-and-plan` when the user wants a checkpoint before commit-volume work begins; `-and-go` when they've said "walk away."
- `/draft-plan` vs `/quickfix` / `/do`: `/draft-plan` is reserved for skills/workflows with non-trivial design surface (integration points, multiple commands, hook interactions). Thin prompt-wrapper changes and prose edits don't need adversarial review — go straight to `/quickfix` or `/do`.
- `/investigate` vs `/quickfix`: `/quickfix` assumes the fix is known. `/investigate` is for bugs where the root cause must be proven before a fix is written. Once `/investigate` lands on a root cause, the fix itself may dispatch `/quickfix` or `/do`.
- `/verify-changes` vs `/qe-audit`: `/verify-changes` checks YOUR recent changes are sound. `/qe-audit` proactively looks for coverage gaps or bugs in the repo at large and files issues. The former gates a commit; the latter generates work.

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
- `/quickfix Fix README typo --force` — low-ceremony PR for trivial changes (no worktree; picks up in-flight edits in main; `--force` skips triage + review)
- `/do Add dark mode. --rounds 2 --force. pr`

Both skills now triage tasks and run a fresh-agent plan review before execution. Use `--force` to bypass.

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
