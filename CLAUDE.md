# zskills -- Agent Reference

## Architecture

Skill distribution repo and presentation site for Z Skills.

- `skills/` — source skill definitions (18 core)
- `block-diagram/` — add-on skills (3)
- `.claude/skills/` — installed skill copies (what Claude Code reads)
- `hooks/` — source hook scripts
- `scripts/` — consumer-customizable stubs (stop-dev.sh, test-all.sh) and release-only repo tooling (build-prod.sh, mirror-skill.sh); skill machinery moved to `.claude/skills/<owner>/scripts/` (port.sh, clear-tracking.sh, statusline.sh in `update-zskills`; plan-drift-correct.sh in `run-plan`; full mapping in `skills/update-zskills/references/script-ownership.md`)
- `CLAUDE_TEMPLATE.md` — template for CLAUDE.md generation in target projects
- `PRESENTATION.html` — main site (index.html redirects here)
- `README.md`, `CHANGELOG.md` — documentation

<!-- ## Dev Server -->
<!-- No dev server — this is a static site / skill distribution repo. -->
<!-- Serve locally with: npx http-server -p 8080 -->

**NEVER use `kill -9`, `killall`, `pkill`, or `fuser -k` to stop processes.** These can kill container-critical processes or disrupt other sessions' dev servers and E2E tests. If a port is busy, check what's on it with `lsof -i :<port>` and ask the user to stop it manually.

<!-- ## Tests -->
<!-- No test suite — this repo contains prompt files and static HTML. -->

**NEVER weaken tests to make them pass.** Do not loosen tolerances, widen mismatch thresholds, skip assertions, or remove test cases to avoid failures. When a test fails, always find the root cause. Fix the code that's broken -- not the test. Only alter a test if the test itself is genuinely wrong (e.g., testing the wrong expected value). Weakened tests will be caught in review and the change will be rejected.

**NEVER modify the working tree to check if a failure is pre-existing.** No `git stash && npm test && git stash pop`, no `git checkout <old-commit>`, no temporary worktrees for comparison. These workflows are fragile -- context compaction between the modification and the restore will lose your changes. If you touched code and tests fail, fix them. If you only touched content (markdown, images, etc.), don't run tests at all.

**NEVER thrash on a failing fix.** If you attempt a fix, run tests, and the same test fails again, STOP. Do not try a third approach to the same problem -- you are guessing and will keep guessing wrong. Report: (1) what you tried, (2) what failed both times, (3) why you think it's failing. Let the user decide the next step. This applies to all retry loops: fix+verify cycles, test failures after cherry-pick, and any "fix -> test -> still fails" pattern. Two attempts at the same error is the maximum.

**Capture test output to a file, never pipe.** Route test output OUT of
the working tree so it never shows up in `git status`. The canonical idiom
is:

```bash
TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
<test-cmd> > "$TEST_OUT/.test-results.txt" 2>&1
```

Then read `"$TEST_OUT/.test-results.txt"` to inspect failures. Never pipe
through `| tail`, `| head`, `| grep` -- it loses output and forces re-runs.
`/tmp/zskills-tests/` is per-worktree-basename, so parallel pipelines do
not collide. The landing script (now bundled in the `commit` skill) removes
the per-worktree dir on successful landing. Always compute `$TEST_OUT` from
`$(pwd)` AFTER you
have `cd`-ed into the correct repo/worktree root; or derive it from an
explicit `$WORKTREE_PATH` the caller passes you (never assume cwd if you
were just handed a path).

**Never suppress errors on operations you need to verify.** Do not use
`2>/dev/null` on commands whose success matters (git worktree remove,
git cherry-pick, rm, mv, cp of important files). Do not use `; echo "done"`
after fallible commands -- use `&& echo "done"` so failure is visible.
After any operation that changes system state (removes a worktree, deletes
files, lands commits), **verify the result** -- check that the directory is
gone, the file is deleted, the commit is on the branch. Past failure: five
worktree removals all silently failed because errors were suppressed with
`2>/dev/null` and `; echo "done"` printed unconditionally.

**Pre-existing test failures.** If a test fails in code you didn't touch,
verify with `git log` that the test/source predates your changes. You may
file a GitHub issue with the error output and mark the test `it.skip('name
// #NNN')`. Never skip tests you wrote or modified.

**NEVER defer the hard parts of a plan.** When implementing a plan, finish all of it -- do not split work into phases and then stop after the easy phase, reframing the remaining work as "next steps" or "future phases." If the plan says to do X, do X. Stopping partway and declaring victory on the easy part undermines progress and the entire project. If you genuinely cannot finish in one session, be explicit that the work is incomplete, not that it's a planned future phase.

**Skill-framework repo — surface bugs, don't patch.** zskills is a skill-framework repo. Every patched-around bug here gets multiplied by every downstream project consuming zskills. When a canary fails, a verifier can't run tests, a hook false-positives, or a tool silently lies, the FIRST instinct must be "surface this as a signal" — never "quietly route around." In a client repo consuming zskills, an agent can reasonably fix a local business-logic bug on the spot; here, every quiet patch is a future debugging session for someone else. If you're tempted to patch, ask: would this fix belong IN the skill/hook/script source, or am I masking a bug to keep moving? If the latter, stop and surface. Past failures this rule has caught: manually exporting `ZSKILLS_PIPELINE_ID` to make a canary pass (real bug was the script's env-var interface → fixed via `--pipeline-id` required); verifier committing with "tests not meaningfully runnable" (real bug was hardcoded `npm run test:all` in two skills → fixed via config-driven three-case tree).

**Memory anchors are agent-local notes, not propagating fixes.** When you surface a skill gap, hook bug, or process discipline failure, saving a memory anchor (`feedback_*.md` under `~/.claude/projects/.../memory/`) only fixes future sessions of the agent that wrote it. Other agents in this session, fresh sessions, and consumers' agents see nothing. To propagate a fix, choose the right surface:

- **CLAUDE_TEMPLATE.md** — for rules every consumer's agent should follow. `/update-zskills` Step B renders this into `.claude/zskills-managed-rules.md`, auto-loaded by Claude Code at session start. Use for cross-project disciplines (e.g., "never call `gh pr merge --auto` directly — dispatch `/land-pr`").
- **Skill SKILL.md prose** — for rules that apply when running a specific skill. Better than CLAUDE.md when the rule is skill-specific. Per skill-versioning enforcement (PR #175), bumping `metadata.version` is mandatory.
- **Helper script** — only when the action is purely mechanical (no judgment) OR the script returns enough information for the agent to judge (e.g., a CI-poll script that returns failure details for the agent to read and act on, not a `handle-ci.py` that tries to handle CI generally on its own).
- **Skill decomposition** — when the gap is structural (a skill is doing too much, or a sub-process needs to be reusable). Extract a sub-skill or split the existing one.
- **Memory anchor** — supplementary to one of the above for the writer's future-session benefit, OR appropriate alone only when the action is genuinely orchestrator-discretionary and not a skill bug (e.g., "prefer concise responses for this user"). Never as the sole response to a surfaced skill gap.

When you save a memory anchor for a process failure, ask: does this need to propagate? If yes, also file an issue (or open a PR) to land the rule in CLAUDE_TEMPLATE.md / the skill / a script. Memory alone leaves the gap open for every other agent.

**Optimize for correctness, not speed.** Follow instructions exactly, including every intermediate verification step. Never skip verification to "save time" -- skipped steps mean the user has to re-verify, which saves nothing. Never stub methods, return bogus values, or simplify implementations to get something working faster. Never reframe the task to make it easier. Review agents will find shortcuts, so cutting corners gains nothing. When the user says "after each step, verify" -- verify after each step, not once at the end.

## Subagent Dispatch

**NEVER dispatch agents on Haiku.** Haiku produces over-literal pattern matches and misses framing -- it greps for an exact string, doesn't find it, and concludes "no bug" when the actual problem is the absence of a guardrail. It is consistently wrong on judgment-class tasks. We do not use Haiku anywhere, period.

When using the Agent tool:

- **Default: omit the `model` parameter** so the subagent inherits the parent's model (typically Opus). This is the safe default.
- **`subagent_type: "Explore"` pins its own model frontmatter to Haiku 4.5 in this environment.** Do NOT use `Explore` without explicitly passing `model: "opus"` (or whichever model the parent is currently using). Prefer `subagent_type: "general-purpose"` -- it inherits the parent model with no override needed.
- Treat any subagent type as Haiku-by-default until you have read its agent definition and confirmed otherwise. When in doubt, pass `model: "opus"` explicitly, or use `general-purpose`.
- **Sonnet** is acceptable only for rare simple+mechanical work (bulk renames, find-replace, format conversion). Never for analysis, review, verification, or judgment.

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
  date: $(TZ=America/New_York date -Iseconds)
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

**Never call `gh pr create` or `gh pr merge --auto` directly when landing a PR.** When you have a feature branch ready to ship, dispatch `/land-pr` via the Skill tool (with `--body-file` and `--result-file`), or use one of its 5 callers (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues`, `/quickfix`) which dispatch `/land-pr` for you with proper rebase, PR creation, CI monitoring (`pr-monitor.sh`), fix-cycle on failure, and auto-merge handling. Direct `gh pr merge --auto` followed by an immediate `gh pr view --json mergeStateStatus` query reports a snapshot state (typically `BLOCKED`) that doesn't reflect resting state — agents who walk away after that snapshot rely on luck. The 5 caller skills are conformance-locked (PR #166 tripwires); follow the same discipline for one-off orchestrator-direct PR landings by dispatching `/land-pr` yourself. (`/land-pr` SKILL.md says "not designed for direct user invocation" — that's about interactive human slash-command typing, not orchestrator agents using the Skill tool. Don't conflate.)

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

## Tracking markers

Tracking markers live in `.zskills/tracking/` and are scoped per pipeline
via a subdirectory named after `PIPELINE_ID`. See
[`docs/tracking/TRACKING_NAMING.md`](docs/tracking/TRACKING_NAMING.md)
for the authoritative scheme, delegation semantics, and migration
strategy. When writing markers from a skill: construct them under
`.zskills/tracking/$PIPELINE_ID/` using the `requires.*`, `fulfilled.*`,
and `step.*` basenames — never flat under `.zskills/tracking/` directly.
Use the sanitize-pipeline-id script (bundled in the `create-worktree` skill;
lands in Phase 2 of the unify plan) before writing any constructed
`PIPELINE_ID` to disk. `.landed` is NOT a tracking marker — it is a separate
worktree-state artifact managed by `/commit land` (via the landing script
bundled in the `commit` skill).

## Skill versioning

**Skill versioning.** Every source skill under `skills/<name>/SKILL.md` and `block-diagram/<name>/SKILL.md` carries a `metadata.version: "YYYY.MM.DD+HHHHHH"` field — date in `America/New_York` plus a 6-char content hash. Edits to a skill body, frontmatter (other than `metadata.version` itself), or any regular file under the skill directory (mode files, references, scripts, fixtures, stubs, etc.) MUST bump this field; the date refreshes to today, the hash is recomputed via `scripts/skill-content-hash.sh`. Pure typo / formatting / whitespace edits do not require a bump (the hash naturally absorbs them since the canonical projection normalizes whitespace; see `references/skill-versioning.md` §3). Enforcement fires at three points: `warn-config-drift.sh` (Edit-time warn, fires only when the file is staged), `/commit` Phase 5 step 2.5 (commit-time hard stop), `test-skill-conformance.sh` (CI gate). The repo-level zskills version (`YYYY.MM.N`) lives in git tags and is mirrored into `.claude/zskills-config.json` by `/update-zskills`.

## Verifier-cannot-run rule

**Verifier-cannot-run is a verification FAIL, not a routing decision.** When a dispatched verification subagent returns without running tests — whether because it hit the `run_in_background: true` + `Monitor`/`BashOutput` anti-pattern, exceeded the 45-minute agent timeout, or returned an empty/no-results response matching one of the stalled-string trigger phrases — the orchestrator MUST invoke the Failure Protocol (STOP, halt the pipeline, surface to the user) instead of logging a one-line note and proceeding. Inline self-verification by the orchestrator is NOT acceptable recovery — the orchestrator wrote the impl prompts and has implementer bias. The structural defense lives in `.claude/agents/verifier.md` (frontmatter `tools:` allowlist excluding `Monitor`/`BashOutput`) and `.claude/hooks/validate-bash-no-background.sh` (frontmatter `PreToolUse` hook rejecting `run_in_background: true`); both must be installed and functional. Past failures: PR #175 (skill-versioning, 2026-05-02) — every Phase 1-6 verifier dispatch hit the Monitor pattern; orchestrator did inline verification across 5 of 7 phases and committed unverified work. Issues #176, #180.
