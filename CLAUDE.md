# zskills -- Agent Reference

> Shared agent rules (Subagent Dispatch, Worktree Rules, Git Rules, Playwright, etc.) auto-load from `.claude/rules/zskills/managed.md`, rendered from `CLAUDE_TEMPLATE.md` via `/update-zskills --rerender`. This file holds project-specific Architecture plus zskills-author-only rules (Tracking markers, Skill versioning, Verifier-cannot-run rule). When editing shared rules, edit `CLAUDE_TEMPLATE.md` and re-run `/update-zskills --rerender` to refresh `managed.md`; the `tests/test-managed-md-up-to-date.sh` conformance gate keeps the two in sync.

## Architecture

Skill distribution repo and presentation site for Z Skills.

- `skills/` — source skill definitions (25 core)
- `block-diagram/` — add-on skills (3)
- `.claude/skills/` — installed skill copies (what Claude Code reads)
- `hooks/` — source hook scripts
- `scripts/` — consumer-customizable stubs (stop-dev.sh, test-all.sh) and release-only repo tooling (build-prod.sh, mirror-skill.sh); skill machinery moved to `.claude/skills/<owner>/scripts/` (port.sh, clear-tracking.sh, statusline.sh in `update-zskills`; plan-drift-correct.sh in `run-plan`; full mapping in `skills/update-zskills/references/script-ownership.md`)
- `CLAUDE_TEMPLATE.md` — template for CLAUDE.md generation in target projects
- `.claude-plugin/` — plugin lane manifests: `plugin.json` (the `zs` plugin) + `marketplace.json` (lists `zs` and `zsbd`); `block-diagram/.claude-plugin/plugin.json` is the `zsbd` addon manifest
- `hooks/hooks.json` — plugin-lane hook registrations (mirrors `.claude/settings.json` but points at `${CLAUDE_PLUGIN_ROOT}`); `hooks/_lib/plugin-hook-skip-if-mirrored.sh` is the D16(a) conditional-skip shim that prevents double-fire when both lanes are installed
- `PRESENTATION.html` — main site (index.html redirects here)
- `README.md`, `CHANGELOG.md` — documentation

**Plugin-lane mental model — internalize this; agents repeatedly get it backwards.** The install states, most-normal first: (1) **Plugin lane, mirror-less = the norm and the goal** — a real plugin consumer has NO `.claude/skills/` mirror, only the 5 materialised artifacts + `.claude/zskills-config.json`, and everything resolves under `${CLAUDE_PLUGIN_ROOT}`; mirror-less is PREFERRED, not a degraded mode. (2) **`/update-zskills` lane, mirrored** = the other supported single-lane state, where the `.claude/skills/` mirror IS the install. (3) **Mirrored-plugin (a `.claude/skills/` mirror present *alongside* a loaded plugin) = dual-install = NOT a supported consumer state** — it exists ONLY in this dogfooding repo and transiently during a lane switch, and the system actively pushes to consolidate it. **The trap: zskills-dev IS case 3** — it carries the mirror because it is the source repo. If you are reasoning here and see `.claude/skills/`, that is the dogfooding exception you are sitting in, NOT the norm you are building for. Never treat the presence of the local mirror as evidence the plugin lane works — validate mirror-less (build the prod-stripped tree, `claude plugin marketplace add` it as a path, install) or you reproduce the "dogfood-mask" that shipped the non-functional plugin lanes in #799/#831.

**Two install lanes — a consumer picks exactly ONE.** A client is single-lane: it installs zskills via the plugin lane OR the legacy `/update-zskills` lane, never both. (Dual-install — both lanes present at once — is a dogfooding-repo / mid-switch transient the system tolerates without corruption and actively pushes to consolidate; see "Dual-path dogfooding" below.) zskills is distributed via (1) the **plugin lane** (`claude --plugin-dir .` loads `.claude-plugin/plugin.json` + `hooks/hooks.json`, resolving paths under `${CLAUDE_PLUGIN_ROOT}`) and (2) the legacy **`/update-zskills` lane** (mirrors `skills/`→`.claude/skills/`, `hooks/*.sh`→`.claude/hooks/`, registers hooks in `.claude/settings.json`, renders `CLAUDE_TEMPLATE.md`→`.claude/rules/zskills/managed.md`). We dogfood BOTH from this repo: plugin-lane via `claude --plugin-dir .` (iterate `edit → /reload-plugins → test`), legacy-lane via `/update-zskills install` (iterate `edit → /update-zskills --rerender → test`). On the plugin lane, the `SessionStart` materialiser (`hooks/session-start-materialise.sh`) writes the 5 consumer-side artifacts (`verifier.md`, `implementer.md`, `inject-bash-timeout.sh`, `verify-response-validate.sh`, and the rendered `.claude/rules/zskills/managed.md`) into `$CLAUDE_PROJECT_DIR/.claude/` on session start — the plugin equivalent of `/update-zskills`'s install-time writes (plugins cannot write at install time). It runs the D27 dual-install probe FIRST and refuses to materialise when the `/update-zskills` lane is already present, so dogfooding both lanes from this repo never clobbers the legacy mirror. Both lanes render `managed.md` through the SAME `scripts/render-managed-rules.py` (D24, one substitution map). See `RELEASING.md` "Dogfooding lanes" and `docs/plans/PLUGIN_DISTRIBUTION.md`. Shipped hook scripts carry a line-2 `# zskills-hook-version:` stamp the shim uses for version-skew defer; bump it when a hook's distribution version changes (Phase 1 introduced the convention; `tests/test-skill-conformance.sh` gates its presence).

**Dual-path dogfooding — a tolerated transient, not a client end-state.** A consumer that lands on both lanes at once (e.g. dogfooding here, or mid lane-switch) is a TRANSIENT state the system tolerates without corruption and actively pushes to consolidate — clients are single-lane (see above). It is kept corruption-free and self-correcting by three structural pieces: (1) the D16(a) conditional-skip shim (`hooks/_lib/plugin-hook-skip-if-mirrored.sh`) sourced by every plugin-registered hook, so a plugin hook with a settings.json-registered same-basename sibling defers (basename match against the OUTERMOST `BASH_SOURCE` entry — portable across the plain-`bash` and claude-harness sourcing semantics — plus a `# zskills-hook-version:` skew guard); (2) the D27 dual-install probe in the SessionStart materialiser, which nags EVERY session (imperative — "dual install is not a supported client state — run scripts/switch-install-path.sh") and refuses to clobber, plus the W6.1 hard-refuse in `/update-zskills` Step 0.7 that blocks an explicit `install`/`--with-addons` from re-creating the mirror on a `detect==plugin` consumer (skipped only while a `.zskills/switch-in-progress` marker is present, so the documented `--to-update-zskills` switch does not deadlock); (3) `bash scripts/switch-install-path.sh {--to-plugin|--to-update-zskills}` (also reachable as `/update-zskills --switch-install-path={to-plugin|to-update-zskills}`), the bidirectional consolidation entry point both WARNs point at — lock-LAST in both directions (`.claude/zskills-install-lane` holds the bare value `plugin`/`update-zskills`). Releases ship both lanes from one dev commit: bump BOTH `plugin.json.version` files in lockstep (D10; `tests/test-plugin-marketplace.sh` asserts equality), then `scripts/build-prod.sh` serves the legacy mirror and `scripts/build-plugin-release.sh` serves the plugin tree (`prod/main` + parallel `prod/<version>` tag, push gated behind `--push`). The plugin-mode CI lane (`.github/workflows/test.yml` `plugin-mode` job) validates both manifests + marketplace (Tier 1 mandatory; Tier 2 best-effort `claude plugin validate --strict`; Tier 3 deferred).

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

**Memory anchors are agent-local notes, not propagating fixes.** When you surface a skill gap, hook bug, or process discipline failure, saving a memory anchor (`feedback_*.md` under `~/.claude/projects/.../memory/`) only fixes future sessions of the agent that wrote it. To propagate a fix, choose the right surface:

- **CLAUDE_TEMPLATE.md** — for rules every consumer's agent should follow. `/update-zskills` Step B renders this into `.claude/zskills-managed-rules.md`, auto-loaded by Claude Code at session start. Use for cross-project disciplines (e.g., "never call `gh pr merge --auto` directly — dispatch `/land-pr`").
- **Skill SKILL.md prose** — for rules that apply when running a specific skill. Better than CLAUDE.md when the rule is skill-specific. Per skill-versioning enforcement (PR #175), bumping `metadata.version` is mandatory.
- **Helper script** — only when the action is purely mechanical (no judgment) OR the script returns enough information for the agent to judge (e.g., a CI-poll script that returns failure details for the agent to read and act on, not a `handle-ci.py` that tries to handle CI generally on its own).
- **Skill decomposition** — when the gap is structural (a skill is doing too much, or a sub-process needs to be reusable). Extract a sub-skill or split the existing one.
- **Memory anchor** — supplementary to one of the above for the writer's future-session benefit, OR appropriate alone only when the action is genuinely orchestrator-discretionary and not a skill bug (e.g., "prefer concise responses for this user"). Never as the sole response to a surfaced skill gap.

When you save a memory anchor for a process failure, ask: does this need to propagate? If yes, also file an issue (or open a PR) to land the rule in CLAUDE_TEMPLATE.md / the skill / a script.

**Optimize for correctness, not speed.** Follow instructions exactly, including every intermediate verification step. Never skip verification to "save time" -- skipped steps mean the user has to re-verify, which saves nothing. Never stub methods, return bogus values, or simplify implementations to get something working faster. Never reframe the task to make it easier. Review agents will find shortcuts, so cutting corners gains nothing. When the user says "after each step, verify" -- verify after each step, not once at the end.

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
bundled in the `commit` skill). The `block-unsafe-generic.sh` hook fence has
been broadened to protect every `.zskills/<subtree>/` (tracking, audit,
issues, dev-server.{pid,log}) — not just `.zskills/tracking/` — so the
ZSKILLS_PATH_CONFIG migration's audit + issues subtrees are equally
guarded against accidental recursive deletion.

## Skill versioning

**Skill versioning.** Every source skill under `skills/<name>/SKILL.md` and `block-diagram/<name>/SKILL.md` carries a `metadata.version: "YYYY.MM.DD+HHHHHH"` field — date in `America/New_York` plus a 6-char content hash. Edits to a skill body, frontmatter (other than `metadata.version` itself), or any regular file under the skill directory (mode files, references, scripts, fixtures, stubs, etc.) MUST bump this field; the date refreshes to today, the hash is recomputed via `scripts/skill-content-hash.sh`. Pure typo / formatting / whitespace edits do not require a bump (the hash naturally absorbs them since the canonical projection normalizes whitespace; see `references/skill-versioning.md` §3). Enforcement fires at three points: `warn-config-drift.sh` (Edit-time warn, fires only when the file is staged), `/commit` Phase 5 step 2.5 (commit-time hard stop), `test-skill-conformance.sh` (CI gate). The repo-level zskills version (`YYYY.MM.N`) lives in git tags and is mirrored into `.claude/zskills-config.json` by `/update-zskills`.

**PreToolUse backstop.** A fourth enforcement point — `hooks/block-stale-skill-version.sh` — fires on every `git commit` Bash invocation in any Claude Code session. It reuses `scripts/skill-version-stage-check.sh` and emits a deny envelope on drift. This closes the bare-`git commit` bypass: `/commit` step 2.5 covers `/commit` invocations, and the hook covers everything else. `git push` is NOT gated locally (see `references/skill-version-pretooluse-hook.md` D2 for rationale; CI's `test-skill-conformance.sh` is the push-time backstop). This includes commits made by the **verifier subagent** (introduced by Plan A, loaded from `.claude/agents/verifier.md`). Per Anthropic's documented design (https://code.claude.com/docs/en/sub-agents §"Hooks in subagent frontmatter"), subagent frontmatter `hooks:` declarations COMPOSE WITH (do not replace) project-level `.claude/settings.json` hooks — so the verifier's frontmatter `inject-bash-timeout.sh` AND the project's `block-unsafe-generic.sh` / `block-unsafe-project.sh` / `block-stale-skill-version.sh` ALL fire on every verifier `git commit`. **Recovery (verifier-side):** the deny envelope's `permissionDecisionReason` carries the stage-check STOP message verbatim — including the exact `bash scripts/frontmatter-set.sh <S>/SKILL.md metadata.version "$today+$hash"` command. The verifier has `Edit` and `Bash` in its tools allowlist (`tools: Read, Grep, Glob, Bash, Edit, Write` per `.claude/agents/verifier.md`) and SHOULD execute the bump inline, then re-stage and re-issue the commit. **Recovery (orchestrator-side, when a non-verifier caller hits the deny):** read the STOP message rendered in the tool-error output, run the suggested bump command, and re-issue the commit. Do NOT treat the deny as "tests failed" — it is a strict pre-flight check, not a test result.

## Verifier-cannot-run rule

**Verifier-cannot-run is a verification FAIL, not a routing decision.** When a dispatched verification subagent returns without running tests — whether because it hit the `run_in_background: true` + `Monitor`/`BashOutput` anti-pattern, exceeded the 45-minute agent timeout, or returned an empty/no-results response matching one of the stalled-string trigger phrases — the orchestrator MUST invoke the Failure Protocol (STOP, halt the pipeline, surface to the user) instead of logging a one-line note and proceeding. Inline self-verification by the orchestrator is NOT acceptable recovery — the orchestrator wrote the impl prompts and has implementer bias. The structural defense (D'' architecture, plan VERIFIER_AGENT_FIX) lives at two layers: **Layer 0 (root cause)** — `.claude/hooks/inject-bash-timeout.sh` is a frontmatter `PreToolUse` hook on Bash that auto-extends every Bash call's `timeout` to 600000 ms (10 min) via the `updatedInput` envelope, so the 120s default that triggers the bg+Monitor recovery reflex never fires. **Layer 3 (universal failure-protocol primitive)** — `.claude/hooks/verify-response-validate.sh` is a script every verifier-dispatching skill pipes the verifier's response through (7-phrase stalled-string whitelist anchored to last 10 lines + 200-byte minimum-length signal); exit 1 means STOP. The verifier agent at `.claude/agents/verifier.md` keeps the FULL tools allowlist (`Read, Grep, Glob, Bash, Edit, Write`) — structural restrictions on `Monitor`/`BashOutput` are no longer needed because Layer 0 prevents the trigger. All three artifacts must be installed and functional. Past failures: PR #175 (skill-versioning, 2026-05-02) — every Phase 1-6 verifier dispatch hit the Monitor pattern; orchestrator did inline verification across 5 of 7 phases and committed unverified work. Issues #176, #180.

See `## Skill versioning` for the verifier subagent's interaction with `block-stale-skill-version.sh` (Plan B PreToolUse backstop): the verifier's frontmatter `inject-bash-timeout.sh` hook composes with project hooks per Anthropic's documented additive behavior, so verifier `git commit` is gated identically to orchestrator-side commits.

**Impl-agent dispatch.** Impl agents (those dispatched to write code, run tests, and/or commit changes by `/fix-issues` PR mode, `/do` PR mode, `/land-pr`'s fix-cycle template, `/run-plan`, and `/quickfix`'s agent-dispatched mode) MUST be dispatched with `subagent_type: "implementer"`. The implementer agent (`.claude/agents/implementer.md`) clones verifier's frontmatter hook (`inject-bash-timeout.sh`), so its Bash calls auto-extend to a 600s timeout. This prevents the bg+Monitor stall pattern that would otherwise fire when a long test suite exceeds the Bash tool's default 120s timeout — symmetric to the Layer 0 protection that verifier dispatches already get. Conformance tripwires in `tests/test-skill-conformance.sh` (section "implementer subagent — impl-dispatch site pins") assert each impl-dispatch site declares `subagent_type: "implementer"`; the assertion fails closed if a future edit drops the directive. (Renamed from `fixer` in PR #366 — the agent isn't only for bug fixes; it also builds new features and refactors.)
