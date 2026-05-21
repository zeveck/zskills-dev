---
title: Issues — General Tracker
status: active
created: 2026-05-15
last_sync: 2026-05-19
---

# Issues — General Tracker

Created by `/fix-issues sync` on 2026-05-15 for issues not covered by domain-specific trackers (QE_ISSUES.md, etc). Each entry: problem + suggested fix + complexity tier.

## Open Issues

### #67 — GitLab (glab) support — deferred until prerequisite plans land

**Labels:** enhancement | **Verdict:** NOT FIXED — author-deferred

**Problem.** ~100+ \`gh\` invocations across 16+ skill files assume GitHub. Consumer on GitLab cannot use zskills as-is.

**Status.** Issue body explicitly defers: "not ready to start yet." Three prereq plans are gating: SCRIPTS_INTO_SKILLS, SKILL_FILE_DRIFT_FIX, CONSUMER_STUB_CALLOUTS. Plus an external prereq (a real GitLab project to test against) is missing.

**Fix outline.** When prereqs land: single host-CLI shim (gh ↔ glab abstraction); not per-skill switching. Full parity at user-visible surface (auto-merge, CI poll, JSON parsing, draft MRs). Planning prompts already drafted at \`plans/GITLAB_SUPPORT_DRAFT_PLAN_PROMPTS.md\`.

**Complexity:** L (multi-plan effort when started). **Action now:** none — leave open as architectural memo.

---

### #217 — Relocate plan execution reports out of \`.zskills/audit/\` (work-trail vs forensic separation)

**Labels:** (none) | **Verdict:** NOT FIXED — author-deferred ("not immediately")

**Problem.** PR #211's path-config refactor framed \`.zskills/audit/\` as gitignored forensic exhaust, but per-plan execution reports written by \`/run-plan\` Phase 5 to \`.zskills/audit/plan-{slug}.md\` are work-trail documentation, not forensic state. Currently 52 historical reports are tracked under audit/ despite the dir being gitignored — hybrid status.

**Fix outline.** Add \`$ZSKILLS_REPORTS_DIR\` config field (or hardcode \`docs/plans/reports/\`); update writers (/run-plan Phase 5, /fix-report, /briefing); update readers (/fix-report Step 2 sign-off scan); migrate existing tracked reports; cross-ref rewrite for plan files referencing old paths; conformance fixture updates.

**Complexity:** L (200-300 LOC + 3-4 phases per author estimate). **Trigger to act:** consumer trips on hybrid tracking inconsistency, OR next minor-release scoping. **Action now:** none — leave open as architectural memo.

---

### #278 — \`/research-and-go\` pipeline abandoned after user interrupt + permissions fix

**Labels:** bug | **Verdict:** NOT FIXED — split into 4 sub-fixes

**Problem.** Pipeline ran Step 0 (tracking setup) but never reached Step 1 (\`/research-and-plan\` invocation). Agent dispatched research sub-agents instead of the formal skill, got interrupted by user for permissions issues, never recovered. Compaction at 15:06 wiped remaining context. Post-compaction agent built features ad-hoc with no plan, no adversarial review, leaving orphaned tracking state.

**Fix outline (4 sub-fixes):**
- **Fix #1 — atomic Step 0+1** (S, /quickfix): single-file prose edit to \`skills/research-and-go/SKILL.md:55-177\` so the same response that ends Step 0 bash issues the \`/research-and-plan\` Skill call.
- **Fix #2 — compaction-resilience PreCompact hook** (L, /draft-plan): no PreCompact hook precedent in repo; new hook event + cross-skill semantics + verification injected text survives compaction.
- **Fix #3 — SessionStart orphaned-pipeline detector** (M, /draft-plan): no SessionStart hook precedent; needs design for stalled threshold, surface format, intentional-resume interaction.
- **Fix #4 — step.* markers** (no-op): already exists per \`docs/tracking/TRACKING_NAMING.md:413-415\`, used by \`/run-plan\`. Bundle thin prose addition into Fix #1.

**Complexity:** Mixed. **Action now:** Fix #1 + #4 prose roll-in (combined /quickfix S). Fix #2 + #3 deferred to /draft-plan when prioritized.

---

### #288 — \`ZSKILLS_PYTHON\` env override (handle python3-vs-python on Windows / non-standard distros)

**Labels:** (none) | **Verdict:** NOT FIXED — scope correction in comment

**Problem.** zskills hardcodes \`python3\` in several places. Windows and some Linux distros only have \`python\` (pointing at Python 3). Currently fails.

**Investigated correction (in issue comment).** Issue body claims "~15 call sites" but verified grep shows only 1 prod \`.sh\` invokes python3 (\`hooks/inject-bash-timeout.sh:51\`). The 19 tests/*.sh hits are bash-internal helpers, not framework runtime. Python files have shebangs (separate channel from bash invocation; keep).

**Fix outline.** Trim scope to: (a) \`ZSKILLS_PYTHON\` envvar in the hook with cheap precedence (\`PYTHON=\${ZSKILLS_PYTHON:-\$(command -v python3 || command -v python)}\`); (b) document Python policy in CLAUDE.md / CLAUDE_TEMPLATE.md. SKIP the PYTHON_CMD helper refactor + sed sweep described in body — would add dead plumbing.

**Complexity:** S (~1h, fix-agent or /quickfix). **Action now:** include in next sprint.

---

### #289 — Drop \`briefing.cjs\` — rejoin the briefing fork (briefing.py wins)

**Labels:** (none) | **Verdict:** NOT FIXED — scope EXPANSION in comment

**Problem.** \`skills/briefing/scripts/\` has both briefing.cjs (1945 lines node) AND briefing.py (1716 lines python), maintained in lockstep via parity tests. The portability promise was implicitly broken when zskills_monitor (PR #111) shipped Python-only; subsequent additions (inject-bash-timeout.sh, render-index.py) compounded. Briefing's dual-impl is now a lone artifact of a dead policy.

**Investigated correction (in issue comment).** Body's plan understates blast radius — verified ~12 additional consumer refs need coordinated edits in same PR: \`skills/update-zskills/SKILL.md:681,743,758,761,806,1402,1623\`; \`references/script-ownership.md:27,63,133\`; \`references/stub-callouts.md:78\`; \`tests/test-update-zskills-migration.sh:88\` (asserts briefing.cjs presence; will fail unless updated lockstep); doc-comment refs in \`zskills_monitor/{server.py:237, collect.py:219}\`; self-refs in \`briefing.py:6,19,52\`.

**Fix outline.** Delete briefing.cjs source + mirror; edit briefing/SKILL.md fallback prose; drop parity-test sections in test-briefing-parity.sh (KEEP smoke tests); update all 12 consumer refs in lockstep; bump version + mirror.

**Complexity:** M (2-3h, /quickfix — plan-review valuable for enumeration). **Action now:** include in next sprint.

---

### #291 — CLAUDE_TEMPLATE.md: add skill-routing decision table

**Labels:** (none) | **Verdict:** NOT FIXED — trivial

**Problem.** Agents in zskills and downstream consumers derive skill-routing decisions from individual skill descriptions or session memory. A central lookup table in CLAUDE_TEMPLATE.md would distribute the model.

**Fix outline.** Add a "Which skill for which input" section to CLAUDE_TEMPLATE.md with a routing table (clear bug → /quickfix; backlog of bugs → /fix-issues N; bug + unknown cause → /investigate; plan ready → /run-plan; plan-scale → /draft-plan; small ad-hoc task → /do). Auto-propagates to consumers via \`/update-zskills\` Step B.

**Complexity:** S (~30min, fix-agent). Single-file edit to CLAUDE_TEMPLATE.md, no skill version bumps (CLAUDE_TEMPLATE.md isn't a skill), trivial /update-zskills round-trip check. **Action now:** include in next sprint.

---

### #293 — \`/quickfix\`: drop PR-only constraint; support worktree/direct landing modes

**Labels:** (none) | **Verdict:** NOT FIXED — Approach A only

**Problem.** \`/quickfix\` currently emits hard error and exits when \`execution.landing != "pr"\` (skills/quickfix/SKILL.md:187-191). Per PR #290 review, this drifts from the project principle "all skills should work in all landing modes." 49 references to PR scaffolding in /quickfix's body confirm Phases 6+7 are PR-shaped.

**Investigated correction.** Approach A in body proposes folding into #292's "new Phase 0a" — but #292 was incorrectly filed (already implemented as WI 1.5.4) and was closed. Approach A pivots to: replace the hard error at SKILL.md:187-191 with a soft redirect message (using same two-line redirect template /quickfix already uses elsewhere). 5-line edit at the same code position — same layer, no Phase-0a entanglement.

**Fix outline (Approach A — small).** Replace lines 187-191's hard error with redirect: worktree mode → "/do worktree" suggestion + exit 0; direct mode → "/commit" suggestion + exit 0. Use the existing two-line redirect printf template.

**Approach B (heavy, deferred).** Native multi-mode rework of Phases 6+7. Plan-scale. /draft-plan when consumers actually want native multi-mode (speculative).

**Complexity:** S (~15min, fix-agent). **Action now:** include in next sprint.

---

### #295 — \`/fix-issues\`: 3-worktree cap addresses only 9p checkout contention, not aggregate live-worktree load

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session

**Problem.** \`/fix-issues\` Phase 3 caps simultaneous worktree-agent dispatches at 3 per message. Justification cited in spec: 9p-filesystem checkout contention. The cap controls **simultaneous \`git checkout\` operations during dispatch**, NOT the number of worktrees alive concurrently. For \`/fix-issues 8\`, dispatch staggers into batches of 3+3+2, but each worktree stays live until PR lands — by mid-sprint, all 8 are concurrently active running tests + verifiers + CI.

**Fix outline.** Add \`execution.max_concurrent_worktrees\` to \`.claude/zskills-config.json\` (default 3). Throttle Phase 3 spawns based on live-worktree count (defined as: worktree dir exists + \`.landed\` marker absent — observable from filesystem, no event tracking). Per-skill option vs hardcode default — design call.

**Complexity:** M (~2-4h, /quickfix). 4-5 acceptance items at the auto-REVISE threshold; /quickfix's plan-review will surface design decisions if needed. **Action now:** include in next sprint.

---

### #297 — \`/do\` should support positional \`auto\` token (parity with /quickfix PR #260)

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session

**Problem.** \`/do pr\` is one of 5 PR-landing callers but doesn't parse positional \`auto\`. Token falls through and ends up in TASK_DESCRIPTION as user prose. \`skills/do/modes/pr.md:174,303\` hardcode comments saying auto-merge stays OFF. Caused this session: \`/do <task> auto pr\` produced PR requiring manual merge despite \`auto\` intent — manual \`gh pr merge --auto\` workaround.

**Root cause.** \`auto\` parsing landed in \`/quickfix\` via PR #260 (\`closes #235, #241\`); parallel update never applied to \`/do\`.

**Fix outline (smallest).** Mirror /quickfix's pattern in \`skills/do/SKILL.md\`: add \`auto\` to trailing-flag pre-parse (case-insensitive positional token), set \`AUTO_FLAG=1\`, strip from TASK_DESCRIPTION, pass \`--auto\` into \`/land-pr\` invocation in \`modes/pr.md\` when AUTO_FLAG=1. Update the two stale comments.

**Complexity:** S (~30min, fix-agent or /quickfix). Verify whether /run-plan + /fix-issues PR mode also lag — if yes, batch all 4 callers; if no, /do alone. **Action now:** include in next sprint.

---

### #300 — \`/fix-issues\` sync: TRACKING_ID / PIPELINE_ID naming mismatch breaks Step 8b fulfilled-marker writes

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session

**Problem.** Sync mode passes \`--tracking-id=$SYNC_ID\` to \`/land-pr\` but never exports \`ZSKILLS_PIPELINE_ID\`. Inside \`/land-pr\` Step 8b, \`PIPELINE_ID\` falls back to \`run-plan.$TRACKING_ID\` (= \`run-plan.fix-issues.sync.$TS\`), which never matches the actual subdir \`fix-issues.$TS\`. Result: \`fulfilled.land-pr.*\` marker silently never written; \`requires.*\` marker remains unsatisfied. Hit 2026-05-16 PR #299 — required manual reconciliation.

**Fix outline.** In \`skills/fix-issues/SKILL.md\` sync mode Step 5 sub-step 2, add \`export ZSKILLS_PIPELINE_ID="$PIPELINE_ID"\` immediately before the \`/land-pr\` Skill dispatch. Mirrors \`/run-plan\` and \`/do pr\` convention (they echo the same for transcript propagation).

**Complexity:** S (single-line addition + version bump + mirror; fix-agent). **Action now:** include in next sprint.

---

### #301 — \`/fix-issues\` sync: gap-detection regex \`[^0-9A-Za-z_]\` doesn't match \`**#NNN**\` markdown bold

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session; reproduced again 2026-05-16

**Problem.** Sync's gap-detection grep \`(^|[^0-9A-Za-z_])#$N($|[^0-9])\` fails to match issue references in markdown bold (\`**#279**\`) or heading positions (\`### #288 — ...\`) due to a grep ERE alternation quirk with the inner character class. Net effect: every sync incorrectly marks already-tracked issues as gaps, then the row-writer duplicates them into \`ISSUES_PLAN.md\`. Confirmed reproducible: \`grep -E '(^|[^0-9A-Za-z_])#288($|[^0-9])'\` returns no match against the literal heading line.

**Fix outline.** Switch the two grep sites in \`skills/fix-issues/SKILL.md\` (Phase 1 sync row-writer membership check + the gap-listing while-loop) from \`grep -qE\` with the alternation regex to \`grep -qP "(?<![0-9])#$N(?![0-9])"\` (PCRE lookarounds, supported by GNU grep on the project's standard environment). Add a fixture exercising both \`**#NNN**\` and \`### #NNN\` formatting.

**Complexity:** S (two regex sites + version bump + mirror + fixture; fix-agent). **Action now:** include in next sprint.

---


### #355 — /cleanup-merged: --review flag for per-branch merit-based recommendations + interactive picker

**Labels:** (none) | **Verdict:** NOT FIXED — `/cleanup-merged` today supports only `--dry-run`; no classifier, no `--review`, no `cleanup.long_running_patterns` config field, no interactive picker.

**Problem.** Current `/cleanup-merged` is conservative-by-design: it only removes branches whose PR is MERGED or whose upstream is `gone`. That leaves a long-tail of trailing state — sprint worktrees never pushed, draftplan worktrees that never shipped, empty stub branches from cron CLEANUP cycles, dirty interrupted worktrees, squash-merged-under-different-name branches. The 2026-05-17 session had 12 trailing worktrees the skill couldn't action; a human-assisted per-branch recommendation table did the triage. Issue asks to mechanize that into a `--review` flag.

**Fix outline.** Edit `skills/cleanup-merged/SKILL.md` to: (1) extend the arg parser (line 55) to accept `--review`; (2) add a classifier loop after the fetch+prune preflight (~line 185) iterating `git for-each-ref refs/heads/` joined with `git worktree list --porcelain` (locked field), `gh pr view --json state`, `git status --porcelain` per worktree, and a `.landed` `status:` parse, applying ordered first-match rules from the issue; (3) emit an alphabetized KEEP/MAYBE/DECIDE/REMOVE table with rule citations; (4) interactive picker reading `<letter>:<verb>` overrides / `all-suggested` / blank / `none`. Add `cleanup.long_running_patterns` (array of branch-name globs, default empty) to `.claude/zskills-config.schema.json`. Mirror to `.claude/skills/cleanup-merged/SKILL.md`. Bump `metadata.version`.

**Complexity:** M. **Action now:** /draft-plan — 10-rule classifier + picker DSL + new config field has enough surface area (rule ordering, locked-worktree edge cases) that adversarial review up-front beats reactive PRs.

### #340 — /qe-audit: require orchestrator-side verification of agent findings before gh issue create + tracker mutation

**Labels:** bug | **Verdict:** NOT FIXED — skill prose still flows agent dispatch → `gh issue create` → tracker mutation with no verification gate.

**Problem.** `/qe-audit` dispatches parallel Explore agents and then takes durable-state actions (`gh issue create`, mutating `$ZSKILLS_ISSUES_DIR/QE_ISSUES.md`) on their reports without an orchestrator-side verification step. In the 2026-05-17 audit, 6 issues were filed in ~3 min and #338 had a factual error ("file deleted" — actually trimmed) that a 10-sec check would have caught. The `feedback_verify_agent_reports.md` memory anchor warns of this but is agent-local; the rule needs to live in skill prose to propagate.

**Fix outline.** In `skills/qe-audit/SKILL.md`: insert a new step between Commit Audit Step 4 and Step 5 (line 190) requiring per-finding verification (Read/grep cited file:line, recursive grep for negative claims, read test files for test-shape claims, `git show` for "fixed by commit X" claims), with the verification command recorded in the issue/tracker body; unverifiable findings go to an "Unverified findings" subsection, not filed. Apply the same rule at Bash mode Step 3b parallel-sweep dispatch (line 246) and at both tracker-mutation steps (lines 194, 279). Renumber subsequent steps. Mirror to `.claude/skills/qe-audit/SKILL.md`. Bump `metadata.version`.

**Complexity:** S. **Action now:** /do pr S.

### #338 — briefing: port-failure invariant lost when briefing.cjs dropped (1690c93)

**Labels:** bug | **Verdict:** NOT FIXED — port-failure regression guard removed in 1690c93 was never re-added on the Python side; no test asserts the invariant today.

**Problem.** PR #312 (commit 1690c93) retired `briefing.cjs` and trimmed `tests/test-briefing-parity.sh`, removing the "Port-failure parity" section that asserted: when `port.sh` is missing, `briefing` exits 0 AND emits no `localhost:` URL. This guarded against a pre-Phase-4 regression where a `port = '8080'` fallback would unconditionally emit `localhost:8080/...`. A future edit to `briefing.py` re-introducing that fallback would pass the entire test suite undetected.

**Fix outline.** Restore a Python-only port-failure test case in `tests/test-briefing-parity.sh` (or a new `tests/test-briefing-port-failure.sh`). Port the fixture from `git show 1690c93^:tests/test-briefing-parity.sh` lines ~145-185: build a fake repo at `/tmp/zskills-briefing-fixture-noport` with `.git` marker but no `.claude/skills/update-zskills/scripts/port.sh`, copy `briefing.py` in, run `summary --since=24h`, assert exit 0 and `grep -c 'localhost:'` == 0. Drop all `briefing.cjs` / node branches from the ported fixture.

**Complexity:** S. **Action now:** /do pr — restore Python-only port-failure test.

### #336 — Dashboard queue normalization: cold-start gh-list failure + client POST wipes user ordering

**Labels:** bug | **Verdict:** NOT FIXED — pruning at `app.js:400-417` runs unconditionally; no `snap.errors` / `issues_fetch_ok` guard exists.

**Problem.** Commit 430fad0 (PR #294) made the dashboard client self-prune its `monitor-state.json` issue queues against the live `gh issue list` result. Two failure modes follow: (1) **cold-start gh-list failure** — when the dashboard restarts with an empty 60s cache and the first `gh issue list` returns non-zero, `collect.py` returns `issues: []` and appends to `snap.errors[]`; (2) **client POST wipes ordering** — `deepCloneQueues` then treats every state entry as "dead" (not in live set), strips them all, and the next user drag POSTs the wiped state, destroying persistent ordering. The 60s cache only helps after one successful fetch lands.

**Fix outline.** Gate the issue-prune loop on absence of a `gh issue list` failure. Cleanest split: server-side, set `snap.issues_fetch_ok = false` in `collect.py` (~line 1068-1162) on the gh-list error paths; client-side, in `static/app.js` `deepCloneQueues` (lines 400-417), skip the `if (!liveIssueNumbers.has(num)) continue` filter when `snap.issues_fetch_ok === false` (or as a fallback, when `snap.errors.some(e => /gh issue list/i.test(e.source))`). Preserve `lastGoodQueues...arr.length` for card-counter UI to keep the stale-good fallback. Add a test exercising mocked `gh` non-zero + fixture state + POST asserting N entries preserved.

**Complexity:** S. **Action now:** /do pr — small, localized two-file change with a clear test path.

### #390 — warn-config-drift.sh mirror is stale — skill-version Edit-time warn never fires in production

**Labels:** bug | **Verdict:** NOT FIXED — `wc -l` confirms 259-line source vs 143-line mirror; `grep -c skill-content-hash` returns 3 in source, 0 in mirror; `.claude/settings.json:56,66` wire the mirror.

**Problem.** `hooks/warn-config-drift.sh` (259 lines) contains Branch 3 (skill content-hash drift WARN, lines 146-256) and a widened Branch 2 regex `(skills|block-diagram)/[^/]+/.*\.md$` (line 62). The `.claude/hooks/warn-config-drift.sh` mirror (143 lines) is the pre-#175 form: Branch 2 regex is the old `skills/[^/]+/.*\.md$` (line 62, no `block-diagram`) and Branch 3 is absent entirely. `.claude/settings.json:56,66` wire the mirror, so Layer 1 of the CLAUDE.md "3-point enforcement" (Edit-time WARN) is silently inert in every Claude Code session. `tests/test-skill-version-enforcement.sh:17` pins `HOOK="$REPO_ROOT/hooks/warn-config-drift.sh"` (source), so CI stays green while production is broken — classic mirror-bypassed-tests pattern.

**Fix outline.** Two coherent steps: (1) `cp hooks/warn-config-drift.sh .claude/hooks/warn-config-drift.sh` to bring the mirror current. (2) Add a conformance test (extend `tests/test-skill-conformance.sh` or new `tests/test-hooks-mirror-parity.sh`) asserting byte-equality between every `hooks/*.sh` source and its `.claude/hooks/*.sh` mirror via `cmp -s` over a globbed list. The conformance test closes the broader class — issue notes every `hooks/` source has a mirror and tests target source.

**Complexity:** S. **Action now:** /do pr — two-file behavioral change (mirror sync + new conformance test) with a clear spec; small enough to skip /draft-plan, but two surfaces (production hook + new test gate) justify pre-execution review over implementer.

---

### #392 — block-unsafe-generic.sh:429 strips wrong side of refspec — `git push origin <local>:main` bypasses main-push block

**Labels:** bug | **Verdict:** NOT FIXED — line 429 still reads `PUSH_TARGET="${PUSH_TARGET%%:*}"`; no test in `tests/test-hooks.sh` exercises a `<localref>:main` refspec.

**Problem.** `hooks/block-unsafe-generic.sh:429` does `PUSH_TARGET="${PUSH_TARGET%%:*}"` with the comment "Strip remote-side of refspec if present (e.g., local:remote)." The bash expansion `${X%%:*}` keeps the text **before** the colon (the local side), so for `git push origin feat:main` `PUSH_TARGET` resolves to `feat`, the equality check at line 431 (`main`/`master`) misses, and the push is allowed even when `BLOCK_MAIN_PUSH=1`. The same shape also evades `hooks/block-unsafe-project.sh.template` rules (a) at line 828 and (b) at line 832 — regex `origin[[:space:]]+[+:]?(main|master)` requires `main` immediately after `origin`, and `HEAD:(main|master)` only catches the literal `HEAD` source, so `feat:main`, `<sha>:main`, `HEAD~3:main` all sneak through main_protected too.

**Fix outline.** Change `hooks/block-unsafe-generic.sh:429` to `PUSH_TARGET="${PUSH_TARGET##*:}"` (longest-match prefix removal — keeps the destination) and fix the inverted comment. In `hooks/block-unsafe-project.sh.template:828-833`, broaden rules (a)+(b) so any `<anything>:(main|master)` refspec under `origin` triggers — e.g. add a third regex `[^[:space:]]+:(main|master)([[:space:]]|$|\")` against `PUSH_ARGS`. Extend `tests/test-hooks.sh` (around line 318 for generic, line 1232 for project) with cases for `feat:main`, `abc123:main`, `HEAD~3:main`, and `+feat:main` — all must deny under both `BLOCK_MAIN_PUSH=1` and `main_protected: true`.

**Complexity:** S. **Action now:** implementer — bounded two-file fix (generic hook line + project template regex) with co-located test additions in one file.

---

### #395 — zskills-resolve-config.sh unit_cmd/full_cmd regex unscoped — sibling block (`ui`) shadows `testing` values

**Labels:** bug | **Verdict:** NOT FIXED — `skills/update-zskills/scripts/zskills-resolve-config.sh:77-82` still uses unscoped `\"unit_cmd\"`/`\"full_cmd\"` regex; reproduced live with `{"ui":{"full_cmd":"UI_WRONG",...},"testing":{...}}` yielding `FULL=[UI_WRONG]`.

**Problem.** Lines 77-82 of `skills/update-zskills/scripts/zskills-resolve-config.sh` (mirrored at `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`) extract `UNIT_TEST_CMD`/`FULL_TEST_CMD` via `[[ "$_ZSK_CFG_BODY" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]` with no enclosing-object anchor, so the FIRST `"unit_cmd"`/`"full_cmd"` key in the JSON wins. Sibling extractions in the same file are properly scoped (`dev_server` line 88, `commit` line 96, `execution` line 108). `output_file` (line 91) shares the same unscoped bug; `detect-language.sh:107-112` repeats the pattern. Any consumer whose config places a `cmd`-named field in a block before `testing` silently runs the wrong test command — verifier subagents would attest "tests pass" against the wrong suite.

**Fix outline.** Rewrite lines 77-82 to scope under `"testing"`, mirroring the `dev_server` pattern at line 88: `\"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"`. Apply the same scoping to `output_file` (line 91, scope under `output` or wherever it actually lives) and to `detect-language.sh:107-112` (scope under `testing`). Add a sibling-collision fixture to `tests/test-zskills-resolve-config.sh` (config with a `ui` block carrying `unit_cmd`/`full_cmd` before `testing`, assert `UNIT_TEST_CMD=TESTING_UNIT`). Mirror to `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`. Bump `skills/update-zskills/SKILL.md` `metadata.version`.

**Complexity:** S. **Action now:** /do pr — two scripts + one test + a mirror copy + version bump; bounded, single-purpose, no design surface to review.

---

### #396 — post-run-invariants.sh:119 Invariant #4 silently passes when ls-remote returns 128 (network/auth)

**Labels:** bug | **Verdict:** NOT FIXED — `.claude/skills/run-plan/scripts/post-run-invariants.sh:119` still uses `if git … ls-remote --exit-code … 2>&1; then`, conflating exit 2 (absent) with exit 128 (origin unreachable / auth fail). The three-way discrimination already shipped in `.claude/skills/commit/scripts/land-phase.sh:161-201` was never propagated here.

**Problem.** Invariant #4 is supposed to fail loudly when a feature branch persists on origin after a landed PR. Because the `if` only fires on rc=0, any non-zero rc — including rc=128 — is treated as "branch absent, invariant satisfied." A broken remote, expired token, or typo'd `origin` URL therefore makes the gate silently pass forever, defeating its stated purpose at `post-run-invariants.sh:17-19` ("mechanical gate that catches silent failures"). The same `2>/dev/null` antipattern recurs at line 180 for Invariant #7 (fetch base branch) — same severity-class bug, separate finding flagged in the body.

**Fix outline.** In both `skills/run-plan/scripts/post-run-invariants.sh:117-123` and its `.claude/` mirror, replace the `if` with the `LS_RC=$? ; case` block from `land-phase.sh:171-200`: rc=0 → INVARIANT-FAIL, rc=2 → pass, anything else → INVARIANT-FAIL with the actual rc surfaced. Drop `2>/dev/null` so stderr surfaces on rc=128. Apply the symmetric treatment to the Invariant #7 fetch at line 180. Bump `metadata.version` on `skills/run-plan/SKILL.md`. The "Larger-than-issue" sweep for a shared `safe-ls-remote-branch.sh` helper is a separate cleanup — out of scope for the direct fix.

**Complexity:** XS. **Action now:** /do pr.

---

### #397 — pr-rebase.sh doesn't verify HEAD == $BRANCH before rebase — silent wrong-branch rebase if CWD mismatches

**Labels:** bug | **Verdict:** NOT FIXED — no `rev-parse --abbrev-ref`/`symbolic-ref`/`checkout`/`switch` anywhere in `.claude/skills/land-pr/scripts/pr-rebase.sh`; `--branch` is consumed only by the existence checks at lines 65-72 (`refs/heads/$BRANCH` + `ls-remote --heads`), and line 83's `git rebase "origin/$BASE"` operates on whatever HEAD points at in the caller's CWD.

**Problem.** `pr-rebase.sh` accepts `--branch <name>` but never asserts `HEAD == $BRANCH` nor `checkout $BRANCH` before rebasing. Lines 65-72 only verify the named branch exists; line 83 then rebases the CWD's current branch onto `origin/$BASE`. A caller that forgets to `cd` into the feature worktree (or runs from main / a stale worktree) gets exit 0 with the named feature branch untouched and possibly a destructive rebase on the wrong branch. This is exactly the silent-no-op class that `pr-push-and-create.sh:104-107` documents as Issue #188 — the fix didn't propagate symmetrically. No `tests/test-land-pr-scripts.sh` fixture exercises HEAD != BRANCH, so there's no regression guard.

**Fix outline.** In `.claude/skills/land-pr/scripts/pr-rebase.sh` (and the source mirror under `skills/land-pr/scripts/pr-rebase.sh`), insert between current step 3 (fetch, line 75-80) and step 4 (rebase, line 82-85) a HEAD check: `CUR=$(git rev-parse --abbrev-ref HEAD)`; if `"$CUR" != "$BRANCH"` emit `REASON=wrong-current-branch` and `exit 11`. Add a `tests/test-land-pr-scripts.sh` fixture using mock-git where `rev-parse --abbrev-ref HEAD` returns a different branch, asserting exit 11 + `REASON=wrong-current-branch` + no rebase invocation. Bump `metadata.version` on `skills/land-pr/SKILL.md`. (Alternative — explicit `git checkout "$BRANCH"` with rc-check — is more invasive given worktree semantics; assertion is safer.)

**Complexity:** S. **Action now:** /do pr — single-script guard + one mock-git test fixture + version bump, fully isolated to the land-pr skill.

---

### #398 — block-main-edits.sh deny message recommends /quickfix — but /quickfix is no-worktree, so same hook denies its edits

**Labels:** (none specified) | **Verdict:** NOT FIXED — `block-main-edits.sh:150` still lists `/quickfix` first in the alternatives list with no agent-dispatched-mode caveat; `quickfix/SKILL.md:6,20` confirm "without a worktree" / "No worktree. No cherry-pick."

**Problem.** When `main_protected: true`, `.claude/hooks/block-main-edits.sh` lines 142-160 emit a deny message whose first recommended alternative is `/quickfix` ("Light, one-commit fix in flight"). But `/quickfix` operates on the main checkout itself (`SKILL.md:6,20,35` — `git checkout -b` on main, dirty tree carried across), so an **agent-dispatched** `/quickfix` invocation (clean tree + description mode) will have its impl-agent's Edit/Write calls denied by the same hook. Result: a denial loop for any agent routed by the deny message. User-edited mode survives only because the human's edits predate the branch (and the hook gates Edit/Write, not `git add`).

**Fix outline.** Edit `.claude/hooks/block-main-edits.sh:150-153` to either (a) drop `/quickfix` from the list and lead with `/do pr` + `/create-worktree`, or (b) qualify it as "user-edited mode only (dirty tree already in place); agent-dispatched mode requires `/do pr`". Option (b) preserves the user-edited path that legitimately works. Mirror the same text into `hooks/block-main-edits.sh` source (if not already symlinked) and confirm no test in `tests/` pins the current wording verbatim.

**Complexity:** XS. **Action now:** /do pr.

---

### #399 — No `is_git_subcommand_in_wrappers` — `bash -c 'git commit'` and `eval 'git commit'` bypass every git-side hook

**Labels:** bug | **Verdict:** NOT FIXED — `hooks/_lib/git-tokenwalk.sh:407` defines only `is_gh_pr_subcommand_in_wrappers`; no git analogue. Carve-out is locked by `tests/test-block-stale-skill-version.sh:264` (C10e) and documented as `#399` in `hooks/block-stale-skill-version.sh:25-36`.

**Problem.** Tokenizer asymmetry: PR #255 added `is_gh_pr_subcommand_in_wrappers` (`hooks/_lib/git-tokenwalk.sh:407-524`) which recursively unwraps `bash -c '<inner>'` / `sh -c` / `eval '<inner>'` for gh-pr gating, but `is_git_subcommand_in_chain` (`hooks/_lib/git-tokenwalk.sh:164`) was never given the parallel `_in_wrappers` form. Consequently `bash -c "git commit --no-verify -m hi"` and friends slip past `block-stale-skill-version.sh:179`, `block-unsafe-project.sh.template:476/483/621/627/706/810`, and `block-unsafe-generic.sh:384/389/400` (commit/cherry-pick/push/add -A/--no-verify). Six call sites unprotected; `bash -c` is a normal idiom orchestrators reach for when constructing dynamic git commands.

**Fix outline.** Clone `is_gh_pr_subcommand_in_wrappers` (`hooks/_lib/git-tokenwalk.sh:407-524`) as `is_git_subcommand_in_wrappers` (drop `flag_regex` is optional — keep parity), thread it through the six call sites in `block-stale-skill-version.sh`, `block-unsafe-project.sh.template`, and `block-unsafe-generic.sh` (replace `is_git_subcommand_in_chain` where wrapper-recursion is wanted, or call wrappers as fall-through). Inline copy into each hook to match the existing inline-copy pattern. Flip `C10e` in `tests/test-block-stale-skill-version.sh:30,264` from `assert_no_match` to `assert_match`, delete the carve-out docstring in `block-stale-skill-version.sh:25-36`, add `is_git_subcommand_in_wrappers` to the helper list in `tests/test-hook-helper-drift.sh:24`, and add positive tests for `bash -c 'git commit'`, `bash -c 'cd /tmp/wt && git commit'`, `eval 'git commit'`, `bash -c "git commit --no-verify"`, plus parallel coverage in `tests/test-block-unsafe-generic.sh` and `tests/test-block-unsafe-project.sh`. Mirror updates into `.claude/hooks/`.

**Complexity:** M. **Action now:** /do pr.

---

### #400 — apply-preset.sh extracts CURRENT_LANDING / CURRENT_PROTECTED with unscoped regex (same class as #395)

**Labels:** bug | **Verdict:** NOT FIXED — `skills/update-zskills/scripts/apply-preset.sh:73-74` still uses unscoped `"landing"` / `"main_protected"` extraction; reproduced live with a multi-line `{"extra":{"landing":"WRONG"},"execution":{"landing":"pr",...}}` yielding `CURRENT_LANDING=WRONG`. Write path at lines 138, 142 is also unscoped and clobbers the sibling.

**Problem.** `skills/update-zskills/scripts/apply-preset.sh:73-74` (mirror at `.claude/skills/update-zskills/scripts/apply-preset.sh:73-74`) extracts `CURRENT_LANDING`/`CURRENT_PROTECTED` via `sed -n -E 's/.*"landing"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1` — no enclosing-object anchor, so on multi-line JSON the first matching line wins regardless of which block it's in. Lower likelihood than #395 today (no plausible parallel `landing`/`main_protected` schema field exists), but worse than the issue describes: the *write* path at lines 138 (`sed_inplace "s/(\"landing\"...)..."`) and 142 (same for `main_protected`) is equally unscoped and would overwrite BOTH siblings, silently corrupting the foreign field. This is install/repair code in `/update-zskills`, so the blast radius reaches every consumer.

**Fix outline.** Apply #395's fix template: scope both reads and both writes to the `"execution"` object, mirroring `dev_server` scoping in `zskills-resolve-config.sh:88` (i.e. `"execution"[[:space:]]*:[[:space:]]*\{[^}]*"landing"...`). Read path: switch the `sed -n` extractions at lines 73-74 to scoped regex (or to a small awk pass over the existing `execution` block — the `EXEC_EXISTS` grep already exists). Write path: the existing `sed_inplace` calls at lines 138, 142 must also be scoped (awk-replace within the `execution` block is cleaner than multi-line sed). Add a sibling-collision fixture to `tests/test-apply-preset.sh` with `{"extra":{"landing":"WRONG"},"execution":{...}}`, assert `CURRENT_LANDING=pr` AND that `extra.landing` is unchanged after a write. Mirror to `.claude/skills/update-zskills/scripts/apply-preset.sh`. Bump `skills/update-zskills/SKILL.md` `metadata.version`. Issue body's "Larger-than-issue" suggestion (Python json-helper sibling to `zskills-resolve-config.sh`) is a separate refactor — out of scope for this fix.

**Complexity:** S. **Action now:** /do pr — two scripts + one test fixture + mirror + version bump; bounded, parallel to #395's fix shape.

---

### #401 — Extract `hooks/_lib/resolve-effective-worktree-root.sh` to consolidate cd-target + LOCAL_ROOT resolution across hooks

**Labels:** (none) | **Verdict:** NOT FIXED — 4 TODO(#401) markers still present (3 in `hooks/block-unsafe-project.sh.template`, 1 in `hooks/block-stale-skill-version.sh`); no helper file in `hooks/_lib/` yet.

**Problem.** The 4-tier precedence (env override → `extract_cd_target` from JSON command → `git rev-parse --show-toplevel` → `$PWD`) is duplicated verbatim at four sites: `hooks/block-unsafe-project.sh.template:546-551` (commit-block), `:646-651` (cherry-pick-block), `:714-719` (push-block), and `hooks/block-stale-skill-version.sh:75-81` (the `extract_cd_target` helper) + `:195-200` (the `EFFECTIVE_REPO_ROOT` resolver). Each site carries an identical TODO(#401) pointing here. Drift risk on the next worktree-blind bug fix.

**Fix outline.** Create `hooks/_lib/resolve-effective-worktree-root.sh` defining `extract_cd_target()` and `resolve_effective_worktree_root()`. Inline both functions verbatim into all four consumer hooks (mirror the `is_git_subcommand` discipline). Extend `tests/test-hook-helper-drift.sh:17` consumer loop + inner `for FN` allowlist to cover the two new function names, then delete TODO comments. Touches 5 files (1 new helper, 2 hook edits, 1 drift test, plus skill-version bumps if hooks ship inside a skill).

**Complexity:** S. **Action now:** /do pr.

---

### #404 — /qe-audit: ban 'audit-not-done' caveats; require validating evidence for cross-cutting concerns

**Labels:** bug | **Verdict:** NOT FIXED — `skills/qe-audit/SKILL.md` Step 5 (lines 212-215) and Step 6 (lines 217-221) contain no ban on "audit-not-done" caveats; "Larger-than-issue"/cross-cutting framing is not addressed; recent issues #380, #390 demonstrate the caveats are still emitted.

**Problem.** `/qe-audit`-filed issue bodies publish deferred-research caveats ("Audit-not-done — a repo-wide sweep would help") and unvalidated structural framings ("Larger-than-issue: mirror discipline is a structural risk") instead of running the cheap audit themselves. Downstream `/fix-issues` triage cannot distinguish theoretical from real wider concerns, over-tiers to `/draft-plan`, and stalls the queue. Past failures: #380 (test-side false-PASS) and #390 (mirror-drift); both audits were a single grep/diff.

**Fix outline.** In `skills/qe-audit/SKILL.md` Step 6 (lines 217-221) and parallel-sweep dispatch in Bash mode (around lines 281-287), insert prose banning "Audit-not-done" caveats in filed bodies, requiring the agent run cheap audits inline and record concrete results, and raising the bar for filing a separate structural issue to "verified concrete instances + high-value." Add a worked right-vs-wrong example citing #380/#390. Bump `metadata.version`, regenerate `.claude/skills/qe-audit/` mirror, and add a string-presence conformance assertion in `tests/test-skill-conformance.sh`.

**Complexity:** S. **Action now:** /do pr.

---

### #408 — /fix-issues Phase 2: source-filter un-researched candidates + auto-research in auto mode (recurring Phase 1 skip)

**Labels:** bug | **Verdict:** NOT FIXED — `skills/fix-issues/SKILL.md` Phase 1 step 5/6 (lines ~1167-1185) are prose-only "should run"; no Phase-2-entry filter exists; cron-fired sprints with un-researched Ready entries proceed to triage on bare titles.

**Problem.** Phase 1 step-5 (gap insertion) and step-6 (research dispatch) are prose-only and have been skipped routinely across ~50 sprints. With no tracker blurb, Phase 2 triages from bare titles + first-200-char body previews — the just-landed #402 independent-sizing discipline (which requires a tracker blurb to read against) does not bite. Symptom 2026-05-18: 21:00 ET dashboard sprint, 11 Ready candidates (#380, #390, #392, #395-#401, #404), none in `docs/issues/*ISSUES*.md`; tracker tops out at #355.

**Fix outline.** Move enforcement to Phase 2 entry and filter at source. After `CANDIDATE_ISSUES` is built (dashboard branch ~line 1420; analogous block at end of "Default rubric"), check each candidate for a `**Action now:**` line within its `### #<N>` section in any `$ZSKILLS_ISSUES_DIR/*.md`. RESEARCHED ones continue; MISSING ones either trigger parallel `general-purpose` research-agent dispatches (auto mode, up to 3 concurrent, block until each commits a tracker row, re-filter) or abort the sprint with a diagnostic pointing at `/fix-issues sync` (interactive mode). Signal is `**Action now:**` (the Phase-2-consumed tier field), NOT `**Verdict:**` (legit `LIKELY FIXED` / `UNCLEAR` / `NOT YET RESEARCHED` values would no-op the gate). Extract filter as `skills/fix-issues/scripts/filter-unresearched-candidates.sh` so tests can call it directly.

**Complexity:** S. **Action now:** /do pr — one filter script + two SKILL.md inserts + tests.

---

### #420 — /land-pr Step 3 parser doesn't map pr-rebase.sh exit 14 (wrong-current-branch) → STATUS empty

**Labels:** (none) | **Verdict:** NOT FIXED — `skills/land-pr/SKILL.md` Step 3 parser block maps only RC 10 and 11; RC 14 (added by #397/#419) falls through to `STATUS=""` empty.

**Problem.** PR #419 (closing #397) added `pr-rebase.sh` exit code 14 for `REASON=wrong-current-branch` (HEAD != $BRANCH assertion). The script-level guard correctly prevents the wrong-branch rebase. However `skills/land-pr/SKILL.md` Step 3 (after `bash pr-rebase.sh ...`) parses REBASE_RC with `if [ "$REBASE_RC" -eq 10 ]; then STATUS="rebase-conflict"; elif [ "$REBASE_RC" -eq 11 ]; then STATUS="rebase-failed"; fi` — RC 14 falls through. Downstream effect: `.landed` marker has no `status: rebase-failed` written for the wrong-branch case; orchestrator's result-file `STATUS` is empty leaving callers ambiguous. The push at Step 4 uses explicit `git push -u origin "$BRANCH"` so the WRONG BRANCH is still NOT pushed — this is a classification gap, not a safety gap.

**Fix outline.** Extend the Step 3 parser in `skills/land-pr/SKILL.md` with `elif [ "$REBASE_RC" -eq 14 ]; then STATUS="rebase-failed"; fi`. REASON is already captured to `wrong-current-branch` via pr-rebase.sh stdout. Mirror to `.claude/skills/land-pr/SKILL.md`. Bump `metadata.version`. Add a unit test against the parser logic.

**Complexity:** XS. **Action now:** /do pr — 3-line addition to one parser block plus mirror + version bump + 1 unit test. Sized down from the verifier's `/do pr` recommendation since the change is purely additive.

---

### #426 — #399 closure incomplete — `bash -c` bypasses 4 destructive-op gates (checkout --, restore, clean -f, reset --hard)

**Labels:** bug | **Verdict:** NOT FIXED — `hooks/block-unsafe-generic.sh:372,377,382,387` still call `is_git_subcommand_in_chain` (confirmed via `grep -n "is_git_subcommand_in_chain\b"`); the converted commit/cherry-pick/push gates at lines 509/516/527 use `is_git_subcommand_in_wrappers`. No `bash -c` test for any of the 4 destructive ops exists in `tests/test-hooks.sh`.

**Problem.** PR #417 (closed #399) threaded `is_git_subcommand_in_wrappers` through 9 add/commit/push sites but left the 4 destructive-op gates in `hooks/block-unsafe-generic.sh` (lines 372 `checkout --`, 377 `restore`, 382 `clean -f`, 387 `reset --hard`) on the original `is_git_subcommand_in_chain` tokenizer. That tokenizer requires the first non-env token to be literal `git`, so `bash -c 'git reset --hard HEAD~5'` / `eval 'git clean -fd'` / `sh -c 'git checkout -- file'` slip past every one of these gates and silently destroy uncommitted state. STASH_BOUNDARY (line 358) is independently exposed: its regex anchors `git[[:space:]]+stash` to `^` or shell separators (`;&|`, `&&`, `||`, backtick, `$(`), none of which precede the inner `git` inside `bash -c 'git stash drop'` — confirmed by reading lines 358-365. Not flagged in the body, but same class.

**Fix outline.** Swap `is_git_subcommand_in_chain` → `is_git_subcommand_in_wrappers` at `hooks/block-unsafe-generic.sh:372,377,382,387` (and any matching `.claude/hooks/` mirror). Convert the STASH_BOUNDARY regex check (lines 358-365) to a wrapper-aware form: either tokenize-then-regex-each-segment, or rewrite as an `is_git_subcommand_in_wrappers "$COMMAND" stash` gate with a flag-check on `$GIT_SUB_REST` for `drop|clear|push|save|-u` and allow `apply|list|show|pop|create|store|branch`. Add `bash -c`/`eval`/`sh -c` cases for each destructive op (5 total) to `tests/test-hooks.sh` near the existing #399 wrapper-bypass block. One-pass audit of remaining `_in_chain` use sites in `block-stale-skill-version.sh` (4 hits) and `block-unsafe-project.sh.template` (2 hits) per the issue's count, marking intentional vs missed. Mirror to `.claude/hooks/`. No skill `metadata.version` bump (hooks aren't skill-versioned).

**Complexity:** S. **Action now:** /do pr — bounded multi-site mechanical port (4 line-swaps + STASH rewrite + tests + mirror + audit), single hook file as the design surface, identical pattern to #399's converted gates. Implementer-tier if STASH_BOUNDARY is split into a follow-up; sized S to keep it in one PR.

---

### #427 — extract_cd_target not wrapper-recursive — bash -c 'cd /tmp/wt && git commit' silently falls back to main-repo (re-opens #391/#393 shape)

**Labels:** bug | **Verdict:** NOT FIXED — live reproduction in issue body: `bash -c 'cd <wt> && git commit'` and `eval 'cd <wt> && git commit'` both yield empty `extract_cd_target` output; classify (post-#417) fires, but `EFFECTIVE_REPO_ROOT` falls back to `$CLAUDE_PROJECT_DIR` (= main), so stage-check / tracking-marker enforcement run against MAIN's empty index and silently pass.

**Problem.** `hooks/_lib/resolve-effective-worktree-root.sh:49-67` sed-extracts a leading `cd <target>` from the OUTER command string only — no wrapper-recursion. PR #417 made the classify check wrapper-aware via `is_git_subcommand_in_wrappers` (`hooks/_lib/git-tokenwalk.sh:223-322`), but left the resolver one-level. Result: hook fires on wrapped commits, but reads MAIN's index. Same shape as #391/#393 worktree-blindness, scoped to `bash -c` / `sh -c` / `eval` wrapper-cd envelopes. Affects all 4 inlined call sites: `hooks/block-unsafe-project.sh.template:686,783,847` (commit/cherry-pick/push tracking enforcement) and `hooks/block-stale-skill-version.sh:335` (stage-check subshell cd).

**Fix outline.** Make `extract_cd_target` wrapper-recursive in place (Option 1 in issue) — mirror `is_git_subcommand_in_wrappers`'s recursion: if the segment's first token is `bash`/`sh`/`dash`/`eval` etc., strip flags, capture the `-c` inner string (or eval's args), strip one quote layer, recurse with bounded depth (3, matching the existing convention). Single helper edit in `hooks/_lib/resolve-effective-worktree-root.sh`; drift gate at `tests/test-hook-helper-drift.sh` then propagates the new body byte-for-byte into the 4 inlined call sites. Add wrapper-cd test cases to both `tests/test-tracking-integration.sh` and `tests/test-skill-version-enforcement.sh` (composed case `bash -c 'cd /tmp/wt && git commit'` — currently zero coverage per issue grep).

**Complexity:** M. **Action now:** /do pr.

---

### #428 — skills/update-zskills/SKILL.md Step 0.5 prose teaches the unscoped extraction pattern that #422 + #423 just fixed in scripts

**Labels:** bug | **Verdict:** NOT FIXED — prose recipe still teaches the pre-#395 pattern

**Problem.** Step 0.5 "Read Config" at `skills/update-zskills/SKILL.md:412-472` documents 16 bash-regex JSON extractions (`project_name`, `unit_cmd`, `full_cmd`, `output_file`, `cmd`, `main_repo_path`, `file_patterns`, `auth_bypass`, `timezone`, `main_protected`, `landing`, `branch_prefix`, `auto_fix`, `max_fix_attempts`, `co_author`, …) all in the unscoped form, e.g. `\"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"` (line 425) and `\"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"` (line 454). PR #422 just scoped `landing`/`main_protected` under `"execution"` in `apply-preset.sh` and PR #423 just scoped `unit_cmd`/`full_cmd`/`output_file` under `"testing"` in `zskills-resolve-config.sh` — yet the canonical recipe any skill author copies from still teaches the broken pattern, making it a fourth reproductive site for the bug class.

**Fix outline.** Two options in issue body: (1) minimal — rewrite the 5-7 ambiguous extractions to use parent-object-scoped regex (`\"<parent>\"[[:space:]]*:[[:space:]]*\{[^}]*\"<field>\"`) and annotate parent; (2) preferred — replace the bash-regex block with a Python json helper invocation (e.g. `bash "$ROOT/scripts/zskills-get-config-field.sh" testing.unit_cmd`) per the "Python is required" rule. Land a conformance assertion at `tests/test-skill-conformance.sh` that greps `skills/update-zskills/SKILL.md` for unscoped patterns on known-parented fields. Bump `metadata.version` and mirror to `.claude/skills/update-zskills/SKILL.md`.

**Complexity:** S. **Action now:** /do pr — single-file SKILL.md rewrite + mirror + version bump + conformance tripwire; option (1) is in-scope here, option (2) (new Python helper) is Larger-than-issue and belongs in a follow-up.

---

### #432 — zskills install shape: own repo doesn't follow consumer pattern (CLAUDE.md monolithic vs `.claude/rules/zskills/managed.md`)

**Labels:** (none) | **Verdict:** NOT FIXED — `.claude/rules/zskills/` does not exist in this repo (confirmed `ls`); root `./CLAUDE.md` is monolithic (266 lines, 11 `^## ` sections); `CLAUDE_TEMPLATE.md` is 362 lines / 15 sections; 8 sections are shared by name (`Architecture`, `Subagent Dispatch`, `Cron-fired prompts`, `Playwright CLI`, `Worktree Rules`, `Git Rules`, `Migration scripts`, `Python is required`) — and the recently-landed `## Cron-fired prompts` rule (commit `452e9c7`, PR #433) was dual-written verbatim into both files. `skills/update-zskills/SKILL.md:938-947` documents the consumer pattern (Step B renders template → `.claude/rules/zskills/managed.md`, auto-loaded recursively, never cross-writes root `./CLAUDE.md`) — a pattern this repo does not eat.

**Problem.** zskills ships consumers an install where `CLAUDE_TEMPLATE.md` is the source-of-truth and consumers' root `./CLAUDE.md` stays user-owned. The zskills repo itself stores those same rules in its monolithic root `./CLAUDE.md` AND in `CLAUDE_TEMPLATE.md`. Every shared-rules edit is a manual dual-write with no tooling guard — PR #433 already had to verify byte-equal section bodies via `diff` post-hoc. Future shared edits (anything in the 8 overlapping sections) accumulate latent drift. CLAUDE.md also has 3 zskills-author-only sections (`Tracking markers`, `Skill versioning`, `Verifier-cannot-run rule`) that legitimately don't belong in the consumer template — so the fix can't be a naive "delete CLAUDE.md, render from template."

**Three options in body (mutually divergent designs, not refinements).**
1. **Self-install** — populate `.claude/rules/zskills/managed.md` from our own `CLAUDE_TEMPLATE.md`, gitignore the rendered file, add a contributor render step. Removes dual-write; requires `/update-zskills` to be re-runnable against zskills's own clone (Step 0 source-locator already supports the repo-clone branch at `skills/update-zskills/SKILL.md:99,142`); root `./CLAUDE.md` shrinks to the 3 author-only sections + a pointer to the rendered file.
2. **Accept the difference, document it** — annotate the duplication in `CLAUDE.md` / contributor docs as upstream-self-hosting. XS effort; latent drift persists.
3. **Strip shared content from `CLAUDE.md`, source-of-truth in `CLAUDE_TEMPLATE.md`, regenerate-on-demand** — small render script + gitignore + contributor discipline. Slightly cheaper than option 1 because no Step B execution against ourselves, but redundant if option 1 already works.

**Fix outline.** None pre-decision — option choice is author-level (durability vs effort vs self-install discipline). If option 1: bounded plan covering gitignore entry, contributor render hook or `/update-zskills` self-run docs, root `./CLAUDE.md` split (keep author-only sections, point to rendered file), migration of pre-existing dual-writes, plus a drift-detection conformance test (`tests/test-claude-rules-mirror-parity.sh` asserting the 8 shared sections in `CLAUDE_TEMPLATE.md` render byte-equal into `.claude/rules/zskills/managed.md`). If option 2: a few-line note in `CLAUDE.md` plus optionally a drift test that asserts the 8 shared section bodies match between `CLAUDE.md` and `CLAUDE_TEMPLATE.md`. If option 3: a render script + the same drift test, scoped to the single direction. The drift-detection conformance test is common to all three actionable variants and is the smallest immediate win — could be filed as a follow-up issue regardless of option choice.

**Complexity:** M-L for option 1 (multi-step: gitignore + split CLAUDE.md + contributor docs + migration + conformance test, with self-install correctness risk), XS for option 2, M for option 3. **Action now:** none — author decision needed on which option (or defer entirely). If author picks option 1 or 3, escalate to `/draft-plan`. If option 2, single `/do pr`. A standalone follow-up issue for the drift-detection conformance test (covering whichever shape lands) is a low-risk parallel track regardless.

---

### #429 — Mode files embed `git rebase origin/main` without HEAD precondition — symmetric to fixed #397

**Labels:** (none) | **Verdict:** NOT FIXED — 3 embedded rebase sites have no HEAD guard; grep for `git rev-parse --abbrev-ref HEAD` / `git symbolic-ref` in either mode file returns zero hits.

**Problem.** PR #419 (closes #397) added a `HEAD == $BRANCH` precondition to `scripts/pr-rebase.sh:82-88` (exit 14, `REASON=wrong-current-branch`). But agent-prose mode files run inline bash that bypasses that helper: `skills/fix-issues/modes/direct.md:48` (`if ! git rebase origin/main; then`), `skills/run-plan/modes/pr.md:20` and `skills/run-plan/modes/pr.md:116` (both bare `git rebase origin/main`). Agent CWD drift retargets the wrong branch silently — same #397 symptom.

**Fix outline.** Port the pr-rebase.sh:82-88 guard inline at each site: capture `ACTUAL_HEAD=$(git rev-parse --abbrev-ref HEAD)`, compare to the surrounding branch variable (`$BRANCH_NAME` in run-plan/modes/pr.md, the issue-loop branch in fix-issues/modes/direct.md), exit with a clear error on mismatch. Bump `metadata.version` on both skills. Add a conformance assertion in `tests/test-skill-conformance.sh` that any `git rebase origin/main` literal in a `skills/**/modes/*.md` file is preceded by a HEAD check (prevent regression).

**Complexity:** S. **Action now:** /do pr.

---

### #448 — verifier scope-creep check uses 'origin/main..HEAD --stat' — phantom deletions when origin advances during verification

**Labels:** bug | **Verdict:** NOT FIXED — `.claude/agents/verifier.md` contains no `origin/main..HEAD` literal nor any `--stat`/scope-creep guidance (confirmed `grep -n` for both patterns returns zero hits). The bare comparison is the implicit pattern verifiers reach for absent explicit guidance, and the file has nothing steering them off it.

**Problem.** Verifier agents performing AC-style "no scope creep" checks run `git diff origin/main..HEAD --stat`. `A..B --stat` shows the SYMMETRIC file-set diff, so files added on `origin/main` after the branch's merge-base appear as "deletions in HEAD". Full-suite verification runs 3-4 min, often overlapping with active landings, so origin/main routinely advances mid-verification. Twice today (2026-05-19/20): once during the PR #447 landing window (PR #446 landed mid-verify, 3 of its files surfaced as phantom "scope creep" in `feat/do-track-managed-md`'s HEAD); once for a sibling agent the same evening. Both REJECTs emitted high-confidence, syntactically-correct "Recovery path" code blocks (`git show origin/main:<f> > <f>`) that, if followed, would have undone the freshly-landed PR inside the worktree and re-verified into APPROVE on a corrupted commit. The failure mode is "verifier confidently misleads agents into destructive recovery actions," not "verifier sometimes false-positives."

**Fix outline.** Option A per issue body — append a paragraph to `.claude/agents/verifier.md`'s scope-creep AC guidance that prefers `git show HEAD --stat` (the commit's own file scope, no comparison) or `git diff $(git merge-base origin/main HEAD)..HEAD --stat` (merge-base diff) over bare `git diff origin/main..HEAD --stat`. Inline-cite the two 2026-05-19/20 occurrences and the destructive-recovery shape so future verifier sessions read the rationale, not just the rule. No skill `metadata.version` bump (`.claude/agents/` is not `skills/<name>/**`). Optional follow-up: a conformance assertion in `tests/test-skill-conformance.sh` that `.claude/agents/verifier.md` contains the new merge-base guidance — locks the prose against silent reversion. Option B (verifier pre-flight rebase) is structural and can wait if the prose fix doesn't bite.

**Complexity:** S. **Action now:** /do pr — single-file prose append to `.claude/agents/verifier.md` (no version bump, no mirror — `.claude/agents/` isn't a skill); optional conformance tripwire adds ~10 lines. Sized S for the bounded prose edit on one design surface.

---

### #459 — PIPELINE_ID construction sites in /run-plan, /commit pr, /draft-plan, /refine-plan skip sanitize-pipeline-id.sh (CLAUDE.md tracking-markers rule)

**Labels:** bug | **Verdict:** NOT FIXED — `grep -c sanitize-pipeline-id` returns 0 for all four skills (`skills/run-plan/SKILL.md`, `skills/commit/modes/pr.md`, `skills/draft-plan/SKILL.md`, `skills/refine-plan/SKILL.md`), while 10 peer skills already wrap their constructions with the sanitize helper.

**Problem.** CLAUDE.md `## Tracking markers` mandates the sanitize-pipeline-id helper before any constructed `PIPELINE_ID` is written to disk, but four skills construct + persist PIPELINE_IDs without it. 23 total non-conforming construction sites: 15 in `skills/run-plan/SKILL.md` (lines 353, 508, 557, 632, 895, 1411, 1762, 1828, 2064, 2131, 2179, 2406, 2428, 2440 — and the bare `echo` form at 495/1203), 1 in `skills/commit/modes/pr.md:88` (`PIPELINE_ID="commit.$BRANCH_SLUG"` with only slash→dash translation), 4 in `skills/draft-plan/SKILL.md` (lines 151, 245, 497, 684), 3 in `skills/refine-plan/SKILL.md` (lines 141, 383, 626). The `tr '[:upper:]_' '[:lower:]-'` step in run-plan's TRACKING_ID derivation does not restrict to `[a-zA-Z0-9._-]+`, so any plan file or branch name with a shell-special char (`;`, `$`, space, backtick, …) propagates that char into `.zskills/tracking/$PIPELINE_ID/...` marker paths and into the sibling-check regexes used by `block-unsafe-generic.sh`.

**Fix outline.** Mechanical sweep: after every raw `PIPELINE_ID=...` assignment in the four skills, append the canonical wrap `PIPELINE_ID="$(bash \"$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh\" \"$PIPELINE_ID\")"` (mirror `skills/fix-issues/SKILL.md:869`). Bump `metadata.version` on all four skills (per skill-versioning enforcement). Add a conformance tripwire in `tests/test-skill-conformance.sh` asserting that every skill which writes `.zskills/tracking/$PIPELINE_ID/...` also contains a `sanitize-pipeline-id.sh` invocation between its first `PIPELINE_ID=` line and its first tracking-marker write — locks the invariant against future regressions in any skill. Leave the run-plan transitional flat-write at lines 2095-2097 untouched (called out as out-of-scope in the issue body).

**Complexity:** M. **Action now:** /do pr — mechanical multi-file sweep across 4 skills (23 sites) + 4 version bumps + 1 conformance tripwire. Sized M (not S) because the conformance assertion needs to scan tracking-marker write-sites to know which skills to gate, and the wrap pattern shows up in multiple bash fences per skill (each fence needs its own wrap, not a single shared helper sourcing). Not L — no design surface, no new commands, single canonical fix shape borrowed verbatim from peer skills.

---

### #457 — block-unsafe-generic.sh: BLOCK_MAIN_PUSH bypassed by bare `git push origin +main` (force-prefix without refspec)

**Labels:** bug | **Verdict:** NOT FIXED — `hooks/block-unsafe-generic.sh:599-606` strips refspec LHS (#392) and surrounding quotes (#399) but never strips a leading `+`; the exact-string equality at line 608 (`[ "$PUSH_TARGET" = "main" ]`) lets `+main`/`+master` fall through to `exit 0`. `tests/test-hooks.sh:378-414` BLOCK_MAIN_PUSH toggle block covers bare `main`/`master` and explicit refspecs but never `origin +main`.

**Problem.** When `BLOCK_MAIN_PUSH=1` (the universal-layer guard that fires regardless of `main_protected`), `git push origin +main`, `git push origin +master`, and `git push -u origin +main` all bypass the deny gate. The refspec-LHS strip at line 599 (`${PUSH_TARGET##*:}`) doesn't help because `+main` has no colon. The project-layer hook (`block-unsafe-project.sh.template`, which only runs under `main_protected: true`) handles `+main` correctly (tested at `tests/test-hooks.sh:1391, 1626`), but the generic hook — the only line of defense when `main_protected` is off — does not. Same bypass class as #392 (refspec direction) and #413 (localref:main).

**Fix outline.** After the existing strips at line 599-606, add a single line: `PUSH_TARGET="${PUSH_TARGET#+}"`. Mirror to `.claude/hooks/block-unsafe-generic.sh`. Extend the `BLOCK_MAIN_PUSH=1` toggle test block at `tests/test-hooks.sh:408-414` with deny cases for `git push origin +main` and `git push origin +master` (and ideally `git push -u origin +main` for the upstream-flag form), mirroring the existing `toggle_test` shape. No skill `metadata.version` bump needed (`hooks/` is not under `skills/<name>/**`).

**Complexity:** S. **Action now:** /quickfix — one-line hook edit + mirror + 2-3 test additions in one fixture block, single-purpose, bounded.

---

### #458 — test-skill-conformance.sh deny-list scanner skips block-diagram/ — false-negative covers the #454 sweep regression mode

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** Three `find` invocations in `tests/test-skill-conformance.sh` — line 1762 (deny-list scanner main loop), line 2040 (positive-side fence-local source-check, `target_root` always passed as `$REPO_ROOT/skills`), and line 2408 (helper-source two-line idiom check) — root the scan at `$REPO_ROOT/skills` only, so `block-diagram/add-block/SKILL.md` and `block-diagram/add-example/SKILL.md` are invisible to the CI deny-list gate. PR #454 explicitly swept 17 `TZ=America/New_York` hits across both block-diagram skills and added the extended-scope sibling scanner for `hooks/`/`scripts/`/`*.py`, but the .md-deny-list scope was never widened — the very surface #454 migrated is unprotected from regression. Existing pre-sweep hits in `block-diagram/add-block/SKILL.md:269,417,735` (`npm start &`, `npm run test:all`) already pass conformance today with no allow-hardcoded markers, confirming the gap is exploitable. The companion live-edit hook `hooks/warn-config-drift.sh:62` already globs `(skills|block-diagram)/...md` correctly, so only the CI backstop is gapped.

**Fix outline.** Change each of the three `find "$REPO_ROOT/skills" -name '*.md'` calls (lines 1762, 2040, 2408) to `find "$REPO_ROOT/skills" "$REPO_ROOT/block-diagram" -name '*.md'`, matching the pattern already used at line 1593 (ensure-worktree scanner). For the line-2040 helper (`scan_skill_md_files_for_resolved_var_self_resolution`), thread the second root through the `target_root` parameter or accept multiple roots. Add a regression fixture to `tests/test-skill-conformance.sh` (or a new `tests/test-skill-file-drift-block-diagram-scope.sh` sibling to `test-skill-file-drift-extended-scope.sh`) that injects a forbidden literal into a temp copy of a `block-diagram/*/SKILL.md` and asserts the scanner flags it. Pre-existing unmarked hits at `block-diagram/add-block/SKILL.md:269,417,735` must be resolved in the same PR (allow-hardcoded markers or migration to resolved variables) — otherwise extending the scanner immediately fails CI. No skill `metadata.version` bump (test files aren't under `skills/<name>/**`).

**Complexity:** S. **Action now:** /do pr — three-line scope-fix in one test file + cleanup of 3 pre-existing block-diagram hits (markers or migration) + new regression fixture. Bounded, single-purpose; sized S (not /quickfix) because the pre-existing-hits cleanup adds a second file's edit scope on top of the test change.

---

### #460 — block-bad-cron hook (#456) didn't fire on a real bad-cron call — needs live-fire verification + session-reload caveat

**Labels:** bug | **Verdict:** NOT FIXED — structural design confirmed sound by post-restart live-fire (issue author's 2026-05-20 07:20 UTC comment: hook FIRED and DENIED after restart), but the documentation gap that caused the original miss remains open. `hooks/block-bad-cron.sh` header (lines 1-37) and `.claude/settings.json` `PreToolUse → CronCreate → block-bad-cron.sh` registration are both correct; neither file warns that the hook only protects sessions started AFTER it lands. `tests/test-block-bad-cron.sh` pipes JSON to the script directly and never asserts the integration-level live-fire path.

**Problem.** Claude Code reads `.claude/settings.json` at session init only — mid-session edits (including a freshly-landed PR like #456 at 06:18 UTC) are not re-loaded into the running session's hook table. The orchestrator session that landed #456 then issued `CronCreate(cron: "17 5 20 5 *", recurring: false)` at 07:16 UTC; the deny envelope never fired because the in-flight session held a pre-#456 hook table with no `CronCreate` matcher. Direct-pipe of the same envelope into the script returns the correct deny — the script itself works. The bug is purely "session activation lag, undocumented." Every future hook landing has the same trap until someone documents it: the author who lands the hook is the least-likely person to benefit from it.

**Fix outline.** (a) Add a 3-5 line `Activation` block to the `hooks/block-bad-cron.sh` header (and mirror to `.claude/hooks/block-bad-cron.sh`) explicitly stating "PreToolUse hooks are loaded at session init; sessions started before this registration landed are NOT protected — restart the session to activate." (b) Add the same caveat to whichever skill prose most plausibly schedules crons (likely `skills/run-plan/SKILL.md` cron-confirm block and any `/fix-issues` cron prose) so the agent scheduling the cron is warned. (c) Optionally add a `tests/MANUAL_LIVE_FIRE.md` recipe (or extend an existing manual-test doc) documenting the post-restart integration check — pipe-into-script unit coverage in `tests/test-block-bad-cron.sh` cannot substitute for the real PreToolUse dispatch path. No skill `metadata.version` bump needed if changes are confined to `hooks/` headers; bump required if any `skills/*/SKILL.md` body is touched.

**Complexity:** S. **Action now:** /quickfix — prose-only documentation additions across 2-3 files (hook header + skill section + optional manual-test doc); structural fix already proven sound by the issue author's restart test, so no design surface remains.

---

### #468 — sanitize-pipeline-id.sh returns empty + exit 0 on empty input → silent flat-marker write under .zskills/tracking/

**Labels:** bug | **Verdict:** NOT FIXED — `skills/create-worktree/scripts/sanitize-pipeline-id.sh` (15 lines total) defines `sanitize_pipeline_id() { printf '%s' "$1" | tr -c 'a-zA-Z0-9._-' '_' | head -c 128; }` with `set -eu` but no empty-input guard; `printf '%s' ""` followed by `tr` and `head -c 128` produces empty stdout and exits 0 for both `bash sanitize-pipeline-id.sh ""` and `echo -n "" | bash sanitize-pipeline-id.sh`. The script ships as both an executable dispatcher and a sourceable function; both call paths exhibit the bug.

**Problem.** When an upstream caller's `PIPELINE_ID` arrives empty (empty env var, empty `.zskills-tracked`, basename of an empty PLAN_FILE, …), the sanitize call returns empty + exit 0 and the caller proceeds with `PIPELINE_ID=""`. Downstream `mkdir -p ".zskills/tracking/$PIPELINE_ID"` resolves to `mkdir -p ".zskills/tracking/"` (no-op) and `echo "$now" > ".zskills/tracking/$PIPELINE_ID/marker.X"` resolves to `.zskills/tracking//marker.X` — bash collapses the double-slash and writes a flat `.zskills/tracking/marker.X` marker. That violates the CLAUDE.md `## Tracking markers` invariant ("never flat under `.zskills/tracking/` directly") and corrupts the pipeline-scoped sibling-check used by `hooks/block-unsafe-generic.sh` (broadened to `.zskills/<subtree>/` per the recent fence widening). 20+ consumer sites are exposed: 15 in `skills/run-plan/SKILL.md`, 4 in `skills/draft-plan/SKILL.md`, 3 in `skills/refine-plan/SKILL.md`, plus `skills/fix-issues/SKILL.md:869`, `skills/research-and-go/SKILL.md:102`, `skills/research-and-plan/SKILL.md:363`, `skills/commit/modes/pr.md:89`, `skills/do/modes/pr.md:61`, `skills/quickfix/SKILL.md:648`, `skills/fix-report/SKILL.md:54`, `skills/draft-tests/SKILL.md:177`, `skills/zskills-dashboard/SKILL.md:60` — all of which would silently emit a flat marker if their constructed input was empty. Empty PIPELINE_ID has no valid use case; the sanitize helper is the natural choke-point to enforce that.

**Fix outline.** Add a single empty-input guard at the top of `sanitize_pipeline_id` (after argument capture, before the `printf | tr | head -c` pipeline): if `"$1"` is empty, emit `sanitize-pipeline-id: empty input — refusing to produce empty PIPELINE_ID` to stderr and `return 1` (function form) / `exit 1` (executable dispatch path at line 14). Bump `metadata.version` on `skills/create-worktree/SKILL.md` (mandatory per skill-versioning enforcement — script under `skills/<name>/scripts/` is part of the skill). Add 2-3 test cases to whichever test fixture covers create-worktree (search `tests/` for existing sanitize-pipeline-id coverage; add fresh `tests/test-sanitize-pipeline-id.sh` if none exists): (a) empty arg → rc=1 + stderr message, (b) empty stdin → rc=1, (c) normal input still works (regression). Optionally extend `tests/test-skill-conformance.sh` with a fixture asserting the guard exists (string-match on the error message or a behavioral pipe-test). No consumer-site changes needed — every existing caller already pipes through the helper, so the loud failure propagates naturally up the `set -e` chain.

**Complexity:** S. **Action now:** /quickfix — one-line guard added to one 15-line script + version bump on one skill + 2-3 unit tests. Bounded, single-purpose, single fix shape, no consumer-site fan-out. Sized S not /do because the change is purely defensive and lives at a single choke-point; the upstream pattern-spread (20+ callers) is irrelevant to the fix scope.

---

### #469 — /verify-changes PIPELINE_ID fallback constructs from $TRACKING_ID without sanitize (4 sites) — same class as #459

**Labels:** bug | **Verdict:** NOT FIXED — `grep -c sanitize-pipeline-id skills/verify-changes/SKILL.md` returns 0, while 4 `: "${PIPELINE_ID:=$MARKER_STEM.$TRACKING_ID}"` fallback-construction lines exist at `skills/verify-changes/SKILL.md:237`, `:413`, `:499`, `:709`. PR #462 (Closes #459) wrapped the construction sites in 4 peer skills (`/run-plan`, `/commit pr`, `/draft-plan`, `/refine-plan`) but did not extend the audit scope to `/verify-changes`; independent verification in this research turn confirms the 4-site count exactly matches the issue body.

**Problem.** Each of the 4 fallback blocks in `skills/verify-changes/SKILL.md` uses the 3-tier priority `PIPELINE_ID=${ZSKILLS_PIPELINE_ID:-}` → read `.zskills-tracked` → `: "${PIPELINE_ID:=$MARKER_STEM.$TRACKING_ID}"`. Tiers 1 and 2 consume already-sanitized values from a parent pipeline; Tier 3 fires when `/verify-changes` runs standalone (no `$ZSKILLS_PIPELINE_ID`, no `.zskills-tracked` in cwd) and constructs a fresh `PIPELINE_ID` from `$TRACKING_ID` without invoking `sanitize-pipeline-id.sh`. CLAUDE.md `## Tracking markers` mandates the sanitize wrap unconditionally before any constructed `PIPELINE_ID` is written to disk; the standalone path violates that invariant, identical class to #459. The constructed value then propagates into `.zskills/tracking/$PIPELINE_ID/...` marker paths and into the sibling-check regexes used by `block-unsafe-generic.sh` — any shell-special char in `$TRACKING_ID` corrupts both.

**Fix outline.** After each of the 4 fallback assignment lines (237, 413, 499, 709) insert the canonical wrap `PIPELINE_ID="$(bash \"$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh\" \"$PIPELINE_ID\")"`, mirroring PR #462's pattern in the 4 peer skills and the reference site at `skills/fix-issues/SKILL.md:869`. Extend the conformance tripwire at `tests/test-skill-conformance.sh:2580-2593` with a 5th `check_sanitize_count "skills/verify-changes/SKILL.md" 4 "skills/verify-changes/SKILL.md"` row to lock the count against future drift. Bump `skills/verify-changes/SKILL.md` `metadata.version` per the standard skill-versioning discipline.

**Complexity:** S. **Action now:** /quickfix — 4 mechanical wrap insertions in a single skill file + 1-line conformance test extension + 1 version bump; single canonical fix shape borrowed verbatim from #462, no design surface, well under the M ceiling that #459 hit (which spanned 4 skills and 23 sites).

---

### #470 — Push-to-main bypass: `feat:+main` slips project hook + `refs/heads/main` slips both hooks (same class as #457)

**Labels:** bug | **Verdict:** NOT FIXED — `hooks/block-unsafe-generic.sh:599-614` already handles `feat:+main` via the layered `${X##*:}` → `${X#+}` normalization (PR #465 closed the `+main` half of this family), but never strips `refs/heads/`, so the fully-qualified `git push origin refs/heads/main` falls through the equality check at line 615 and `exit 0`s. `hooks/block-unsafe-project.sh.template:1035` (rule a) accepts `[+:]?` but no `refs/heads/` prefix; line 1045 (rule b) has neither `[+]?` after the colon nor a `refs/heads/` prefix. So under `main_protected: true`: `feat:+main`, `refs/heads/main`, `+refs/heads/main`, and `feat:refs/heads/main` all slip the project hook; under universal `BLOCK_MAIN_PUSH=1` the generic hook also misses every `refs/heads/main` form. `tests/test-hooks.sh` BLOCK_MAIN_PUSH toggle block (lines 378-414) and project-hook fixtures (lines 1391, 1626) have no `refs/heads/` cases.

**Problem.** Two distinct surfaces, both in the #457 push-to-main family. (1) Generic hook (`hooks/block-unsafe-generic.sh:599-614`): the `+`-strip added by #465 fires only after `${X##*:}` colon-RHS extraction, so `feat:+main` correctly reduces to `main` and is blocked — but `refs/heads/main` has no colon and no leading `+`, so it survives every existing normalization and equality-compares as a literal string against `"main"`, returning false. `git check-ref-format refs/heads/main` returns 0 and `git push origin refs/heads/main` is accepted as equivalent to `main`. (2) Project hook (`hooks/block-unsafe-project.sh.template:1031-1058`): rule (a) regex requires `main`/`master` immediately after `origin `, missing `refs/heads/main`; rule (b) regex requires `main`/`master` immediately after `:`, missing both the optional `+` (sister rule a has it) and any `refs/heads/` prefix. Net: under `main_protected: true` (the most security-sensitive deployment), an agent can push to main via `feat:+main`, `refs/heads/main`, `+refs/heads/main`, or `feat:refs/heads/main`. Same class as #457 / #392 / #413.

**Fix outline.** (a) Generic hook: after the existing `${X#+}` strip at line 614, add `PUSH_TARGET="${PUSH_TARGET#refs/heads/}"`. Mirror to `.claude/hooks/block-unsafe-generic.sh`. (b) Project hook template (line 1035): change rule (a) regex to `origin[[:space:]]+[+:]?(refs/heads/)?(main|master)([[:space:]]|$|\"|\')`. (c) Project hook template (line 1045): change rule (b) regex to `(^|[[:space:]])[^[:space:]]*:[+]?(refs/heads/)?(main|master)([[:space:]]|$|\"|\')` — adds both the `[+]?` and `(refs/heads/)?` prefixes. Mirror to `.claude/hooks/block-unsafe-project.sh.template` (and any rendered live copy if applicable). Extend `tests/test-hooks.sh`: in the BLOCK_MAIN_PUSH toggle block (lines 408-414) add `toggle_test` deny cases for `git push origin refs/heads/main` and `git push origin +refs/heads/main`; in the project-hook fixture block add `expect_deny` cases for `feat:+main`, `refs/heads/main`, `+refs/heads/main`, and `feat:refs/heads/main`. No skill `metadata.version` bump (`hooks/` is not under `skills/<name>/**`).

**Complexity:** S. **Action now:** /quickfix — one-line generic-hook strip + two regex-prefix tweaks in one template file + mirrors + 4-6 test additions in two existing fixture blocks; single-purpose bypass-closure, bounded, mechanical.

---

### #478 — Hooks: no `git rebase` / `git switch --discard-changes` / `git switch -f` guards (analog of blocked `git checkout --`)

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n 'rebase\|switch' hooks/block-unsafe-*.sh*` returns zero hits. `hooks/block-unsafe-generic.sh:404-424` gates `git checkout --`, `git restore`, `git clean -f`, and `git reset --hard` via `is_git_subcommand_in_wrappers`, but has no analogous block for `git switch --discard-changes` or `git switch -f|--force`. `tests/test-hooks.sh:89-97` covers `git checkout --` parallel cases (`expect_deny`/`expect_allow`) but has zero `switch`/`rebase` fixtures.

**Problem.** Of the three commands in the title, two are direct functional analogs of the already-blocked `git checkout --` and one is not: (1) `git switch --discard-changes <branch>` is the documented modern equivalent — git's own docs say "throw away local modifications" — and unambiguously destroys uncommitted working-tree changes; (2) `git switch -f|--force <branch>` likewise throws away local modifications when the target diverges; (3) `git rebase` is generally recoverable (HEAD@{1} reflog + `--abort` restore work), so a blanket block would false-positive on normal rebase workflows and contradict the `-X theirs` rescue patterns CLAUDE.md actively teaches. Agents following modern git advice ("prefer `switch` over `checkout`") get unexpected destructive behavior past the guard — same closure-incomplete pattern as #399/#426/#427 left for the destructive-op family.

**Fix outline.** Add two new gates immediately after the existing `git checkout --` block in `hooks/block-unsafe-generic.sh:404` using the same `is_git_subcommand_in_wrappers` + `$GIT_SUB_REST` regex shape: (a) `if is_git_subcommand_in_wrappers "$COMMAND" switch && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])--discard-changes([[:space:]]|$) ]]; then block_with_reason "BLOCKED: git switch --discard-changes discards uncommitted working-tree changes — modern analog of git checkout --."` (b) `if is_git_subcommand_in_wrappers "$COMMAND" switch && [[ "$GIT_SUB_REST" =~ (^|[[:space:]])(-f|--force)([[:space:]]|$) ]]; then block_with_reason "BLOCKED: git switch -f|--force can discard uncommitted changes on a divergent target."`. Leave `git rebase` unguarded (cite recoverability + CLAUDE.md's documented use of `-X theirs`); CLAUDE.md's "`--ours` and `--theirs` are inverted during rebase vs merge" rule remains the discipline layer. Mirror to `.claude/hooks/block-unsafe-generic.sh`. Extend `tests/test-hooks.sh` parallel to the existing `git checkout --` block (lines 89-97): `expect_deny "git switch --discard-changes <branch>"`, `expect_deny "git switch -f <branch>"`, `expect_deny "git switch --force <branch>"`, plus `expect_allow "git switch <branch>"` and `expect_allow "git switch -c newbranch"` as negative controls. No skill `metadata.version` bump (`hooks/` is not under `skills/<name>/**`).

**Complexity:** S. **Action now:** /quickfix — two short deny-blocks in one hook file + mirror + 3-5 test additions parallel to the existing `git checkout --` fixture block; rebase explicitly out of scope per recoverability analysis, single-purpose, bounded.

### #473 — Dashboard /api/plan/<slug> activity filter uses wrong key (`pipeline_id` vs actual `pipeline`) — always returns empty

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n '"pipeline_id"' skills/zskills-dashboard/` returns exactly one hit (`scripts/zskills_monitor/server.py:840`); `grep -n '"pipeline"' skills/zskills-dashboard/scripts/zskills_monitor/collect.py` shows the emitter writes `"pipeline"` at lines 727 (`"pipeline": pipeline`), 763, and 918. The filter at `server.py:840` (`slug in str(a.get("pipeline_id", ""))`) reads a key the data side never writes, so `parsed["activity"]` is always `[]` for every plan slug.

**Problem.** `skills/zskills-dashboard/scripts/zskills_monitor/server.py:838-841` builds `parsed["activity"]` by filtering `_collect._scan_tracking_markers(...)` records on key `pipeline_id`, but `skills/zskills-dashboard/scripts/zskills_monitor/collect.py:727` (subdir-marker emit) and `:763`/`:918` (legacy flat-marker emit) only ever set key `pipeline` on the records. `a.get("pipeline_id", "")` returns `""` for every record, so `slug in ""` is `False` for every non-empty slug, so the plan modal's Activity section is silently empty for every plan. Canonical key is `pipeline` (data side, three emit sites, also used as the dict key for `location: "pipeline"` enrichment and matches the `.zskills/tracking/$PIPELINE_ID/` subdir naming throughout the codebase) — the filter is the lone outlier. `tests/test_zskills_monitor_server.sh:328-355` exercises `/api/plan/<slug>` for 200/404/400 status only and never asserts on `activity[]` contents, which is why the bug shipped clean.

**Fix outline.** Single-character rename at `server.py:840`: change `a.get("pipeline_id", "")` to `a.get("pipeline", "")`. Add one test in `tests/test_zskills_monitor_server.sh` that seeds a `.zskills/tracking/<pipeline-containing-slug>/` marker before hitting `/api/plan/<known-slug>` and asserts `len(parsed["activity"]) > 0` — closes the test gap the issue body calls out (assertions currently stop at HTTP status codes, never inspect array contents). Defense-in-depth via also matching on the record's `id`/`basename` field is optional and noted in the issue but not load-bearing — the slug-in-pipeline-id substring match is the documented behavior and works once the key is correct. Bump `skills/zskills-dashboard/SKILL.md` `metadata.version` since the fix touches the skill subtree (`skills/zskills-dashboard/scripts/zskills_monitor/server.py`).

**Complexity:** S. **Action now:** /quickfix — one-key rename in one filter call site (single line edit) + one test seeding a tracking marker and asserting activity-array population; canonical key is unambiguous (filter is the lone outlier against three emit sites), so no multi-site rename judgment call. Trivial, single-purpose, bounded.

---

### #479 — block-agents.sh: `subagent_type: Explore` bypasses Haiku-prevention (no .claude/agents/Explore.md → DISPATCH_MODEL empty → allow)

**Labels:** bug | **Verdict:** NOT FIXED — `ls .claude/agents/` returns only `implementer.md` and `verifier.md` (no `Explore.md`); `hooks/block-agents.sh.template:107-145` resolves `DISPATCH_MODEL` in three steps (tool_input.model → `.claude/agents/<subagent_type>.md` frontmatter → empty=allow), and the empty fallthrough at `if [ -z "$DISPATCH_MODEL" ]; then exit 0; fi` (line ~144) silently passes when no per-type agent file exists.

**Problem.** Built-in Claude Code subagent types (`Explore`, `general-purpose`, `claude`, etc.) ship without project-side `.claude/agents/<type>.md` files because their frontmatter lives in the hosting environment, not the repo. CLAUDE.md `## Subagent Dispatch` is unambiguous: *"`subagent_type: Explore` pins its own model frontmatter to Haiku 4.5 in this environment. Do NOT use `Explore` without explicitly passing `model: "opus"`."* But because the hook's Step 2 file-existence check (`[ -f "$AGENT_DEF" ]` at line ~118) yields nothing for `Explore.md`, `DISPATCH_MODEL` stays empty and Step 3's empty-string check exits 0 with the dispatch allowed — the Haiku-prevention hook silently green-lights the Haiku dispatch. Of the listed built-in types, `Explore` is the dangerous one (Haiku-pinned per environment frontmatter); `general-purpose` inherits parent (so empty-allow is actually correct for it).

**Fix outline.** Cleanest fix: ship `.claude/agents/Explore.md` (and mirror to source if there is one) with `model: opus` frontmatter, matching the existing project pattern that pins `implementer`/`verifier` definitions — this re-pins Explore at project level so Step 2 resolves to `opus`. More defensive layered fix: extend `hooks/block-agents.sh.template` Step 3 with a known-Haiku-pinned subagent_type list (initially `Explore`); when DISPATCH_MODEL is empty AND `SUBAGENT_TYPE` matches an entry in that list, deny with a STOP message citing the CLAUDE.md rule. Add `tests/test-block-agents-*.sh` (or extend wherever the agent-min-model test lives) with: `subagent_type: Explore` + no `model:` field → expect DENY (or expect opus resolution if Option 1). Mirror to `.claude/hooks/block-agents.sh` if a rendered live copy exists. No skill `metadata.version` bump (`hooks/` and `.claude/agents/` are not under `skills/<name>/**`).

**Complexity:** S. **Action now:** /quickfix — one new `.claude/agents/Explore.md` (3-line frontmatter) is the floor fix and resolves the production bypass immediately; the defensive list-based deny in `block-agents.sh.template` is a small additive guard with one test case; single-purpose closure of one named built-in subagent-type's bypass. Future built-in types (`general-purpose`, `claude`) can extend the same list as their environment pinning is documented — out of scope here.

---

### #481 — pr-rebase.sh: missing dirty-tree precondition — generic `rebase-failed` doesn't categorize uncommitted-changes vs real conflicts

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n 'git status\|porcelain' skills/land-pr/scripts/pr-rebase.sh` returns zero hits; the script's flow (lines 90-133) goes fetch → `git rebase "origin/$BASE"` (line 99) → on failure check for U-state files (line 107). A dirty working tree causes `git rebase` to refuse before any checkout, hitting either the conflict branch (if `git diff --diff-filter=U` happens to surface anything from prior state, unlikely) or — far more commonly — the line-130 generic terminus emitting `REASON=rebase-failed` exit 11. `/land-pr` Step 3 (`skills/land-pr/SKILL.md:276,279`) maps exit 11 to `STATUS=rebase-failed` with no dirty-tree differentiation, so the user/orchestrator sees the same surface as a network failure, an abort failure, or a non-conflict rebase error.

**Problem.** `skills/land-pr/scripts/pr-rebase.sh` has no `git status --porcelain` precondition before invoking `git rebase "origin/$BASE"` at line 99. Per CLAUDE.md *"Protect untracked files before git operations"*, fallible rebase ops should pre-check the worktree. Today, a dirty worktree produces `REASON=rebase-failed` exit 11 — indistinguishable from the line-130 non-conflict rebase failure, the line-95 network failure, and the line-121 abort-failed terminus, all of which share exit 11. The `/land-pr` Step 3 parser at `skills/land-pr/SKILL.md:276,279` maps exit 11 → `STATUS=rebase-failed` with whatever `REASON` token was emitted, but `rebase-failed` is itself a catch-all; there's no `STATUS=dirty-tree` or `REASON=dirty-working-tree` variant for the orchestrator to surface a clear "commit/stash first" message. Same closure-incomplete categorization pattern as #420 (RC 14 mapping fix).

**Fix outline.** Add an explicit precondition immediately after the arg-parse block (before the `git rev-parse --is-inside-work-tree` check at line 58, or right after it — between current lines 63 and 65 is the safe slot): `if [ -n "$(git status --porcelain 2>/dev/null)" ]; then echo "ERROR: pr-rebase.sh: working tree has uncommitted changes — commit or stash first" >&2; echo "REASON=dirty-working-tree"; exit 16; fi`. Use a new dedicated exit code (16) — 11 is already overloaded across not-a-repo / branch-absent / network / abort-failed / generic-rebase-failed terminus, and reusing it defeats categorization. Mirror to `.claude/skills/land-pr/scripts/pr-rebase.sh`. Update `skills/land-pr/SKILL.md`: extend the Step 3 exit-code parser (around lines 270-289) with a `16) STATUS="dirty-tree"; REASON="dirty-working-tree" ;;` arm, add `dirty-tree` to the `STATUS=` enum at line 158, add it to the failure-terminus skip-list at line 398 and the failure-classification table at line 642 + outcome map at line 691 (`dirty-tree`) so it terminates the pipeline like the other rebase failures. Extend `tests/test-land-pr-*.sh` with a fixture that seeds an uncommitted change before invoking `pr-rebase.sh`, asserts exit 16 + `REASON=dirty-working-tree` + clear stderr message. Bump `skills/land-pr/SKILL.md` `metadata.version` per the standard skill-versioning discipline (script + SKILL.md both touched).

**Complexity:** S. **Action now:** /quickfix — one precondition block in pr-rebase.sh (4 lines) + script mirror + new exit-code arm in the Step 3 parser + ~6 STATUS-list/enum/skip-list/outcome-map insertions in SKILL.md + 1 fixture test + 1 version bump; canonical single-purpose categorization gap closure, single skill, mechanical, well under M ceiling. Mirrors the resolution pattern of #420 (the prior RC-14 mapping fix from this same audit pass).

---

### #482 — pr-monitor.sh: missing post-force-push grace period — first poll after `git push --force` false-fails (memory anchor confirms repeated incidents)

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n 'force.push\|force-push\|grace\|sleep.*re.poll' skills/land-pr/scripts/pr-monitor.sh` returns zero hits; Step 5 re-check (`skills/land-pr/scripts/pr-monitor.sh:113-126`) is a single `gh pr checks` call with no retry/grace, and Step 6b auto-rebase loop in `skills/land-pr/SKILL.md:489-507` invokes `pr-monitor.sh` immediately after `git push --force-with-lease origin "$BRANCH"` (line 470) without any sleep between push and poll.

**Problem.** GitHub CI takes a few seconds to register a new workflow run after a force-push; during that window `gh pr checks <N>` either returns the stale prior run's checks (often `rc=1`/fail from a prior pre-rebase failure) or no-checks-yet. `pr-monitor.sh` Step 5 trusts the first `gh pr checks` exit code unconditionally (`0=pass, 1=fail, 8=pending`) — so the post-force-push call lands in the race window and the script emits `CI_STATUS=fail` for a CI run that's actually about to start and pass. The Step 6b auto-rebase loop then breaks with `STATUS=auto-rebase-blocked REASON=auto-rebase-ci-fail-iter$AUTO_REBASE_ITER` (SKILL.md:504-506) when the rebased commit would have passed cleanly. User memory anchor `feedback_pr_monitor_false_fail.md` documents 3+ false-fail observations in a single 2026-05-17 session; the documented workaround ("sleep 5 + re-poll catches the real status") is currently caller-layer compensation that the script's contract doesn't provide.

**Fix outline.** Primary fix lives in `skills/land-pr/scripts/pr-monitor.sh` Step 5: when the first `gh pr checks` (line 116) returns `rc=1` (fail), sleep 5-10s and re-run the exact same call once; only emit `CI_STATUS=fail` if the second call also returns `rc=1`. Adds at most 5-10s to a real CI failure (acceptable — the script already waits 600s on `--watch`) and eliminates the documented false-fail. Optional: parameterize via `--post-force-push-grace SEC` flag (default 0; Step 6b passes `--post-force-push-grace 10`) for explicit caller opt-in; the unconditional in-script guard is simpler and matches the issue body's recommended Option 1 ("5s grace + one extra re-check"). Bump `skills/land-pr/SKILL.md` `metadata.version` since the script lives under the skill subtree. Test gap (issue notes): no test exercises the post-force-push race — a synthetic `gh` stub returning `fail-then-pass` could exercise the new grace path, but skipping it is acceptable for a small script-internal change.

**Complexity:** S. **Action now:** /quickfix — single-script edit (5-10 lines: detect `RECHECK_RC=1`, sleep, re-run, second result wins), no caller-side prose changes required (Step 6b inherits the corrected contract for free), one `metadata.version` bump on `skills/land-pr/SKILL.md`. Single-purpose, bounded, no judgment call (the grace is on the documented failure path only).

---

### #472 — Sprint /land-pr finalization: double-prefix SPRINT_ID path + leading-cd extract_cd_target collision (self-flagged in PR #467, never filed)

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n SPRINT_ID skills/fix-issues/SKILL.md` confirms `SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$ISSUE_TITLE_SLUG"` at line 867 (already has `sprint-` prefix); the helper `skills/create-worktree/scripts/create-worktree.sh:194` builds `${PROJECT_NAME}-${P}-${SLUG}` → `zskills-fix-issues-sprint-<id>` (single `sprint-`) when called with `--prefix fix-issues` and `SPRINT_ID` as slug, so any orchestrator-side ad-hoc script that re-prepends `sprint-` (e.g. `WT_PATH="/tmp/zskills-fix-issues-sprint-${SPRINT_ID}"`) doubles the prefix. The lived incident is verbatim at `docs/reports/SPRINT_REPORT.md:1117` ("First attempt: a bash var was `/tmp/zskills-fix-issues-sprint-${SPRINT_ID}` where SPRINT_ID already contains `sprint-` prefix → double-prefix path, `cd` silently failed without `|| exit`, downstream ran on main"). `extract_cd_target` at `hooks/block-unsafe-project.sh.template:323-420` extracts the first `cd` target from the command pipeline (regex `^cd[[:space:]]+([^[:space:]\&\;\|]+)` at line 411) — its design picks the FIRST cd, then `resolve_effective_worktree_root` (line 424) trusts that cd target over the ambient cwd. A chain like `cd /workspaces/zskills && ... && cd $WORKTREE && git push` resolves operating root to main and blocks the push.

**Problem.** Bug A: `skills/fix-issues/SKILL.md:867` defines `SPRINT_ID` with a `sprint-` prefix baked in. The skill's own worktree gate at lines 953-954 correctly calls `ensure-worktree.sh --prefix fix-issues "${SPRINT_ID}"`, which yields `/tmp/zskills-fix-issues-sprint-<rest>` (single prefix) — fine. But orchestrator-side finalization scripts (not the skill body itself) reconstruct the path with the literal template `/tmp/zskills-fix-issues-sprint-${SPRINT_ID}` and double the prefix; the resulting `cd` silently no-ops because no `|| exit` is paired, and downstream `git push`/`git commit` runs on whatever cwd was already set (typically main). Bug B: `hooks/block-unsafe-project.sh.template:411` regex picks the first `cd` token only. Sprint Phase 5/6 prose patterns and orchestrator scripts that lead with `cd /workspaces/zskills` (main) before a later `cd $WORKTREE && git push` get the first-cd target resolved to main, `is_on_main()` returns true, and the hook blocks the push at the worktree-cd step. Recovery in the live incident required entering the bash invocation directly inside the sprint worktree (no leading cd-to-main). Neither bug is exercised by `tests/test-fix-issues-*.sh` — both surfaced only when an actual sprint ran finalization end-to-end.

**Fix outline.** Bug A: this is an orchestrator-script bug (not skill-body bug); the durable fix is to surface the correct path through a single source of truth instead of letting orchestrator scripts reconstruct it. Two options: (a) have the worktree gate persist `$WT_PATH` to `/tmp/zskills-current-wt-${SPRINT_ID}` (or similar) and require finalization scripts to read it rather than reconstruct; (b) document explicitly in skill Phase 5/6 prose that `SPRINT_ID` already contains the `sprint-` prefix and orchestrator-built paths must NOT re-prepend, with a worked-example template `WT_PATH="/tmp/${PROJECT_NAME}-fix-issues-${SPRINT_ID}"` (no extra `sprint-`). Either way, also harden the construction with `cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed" >&2; exit 1; }` per the skill's own gate pattern at line 977. Bug B: harder — the hook's first-cd extraction is structural. Right fix is to teach skill prose (and the orchestrator) NOT to lead with `cd /workspaces/zskills` when later commands target a worktree. Replace `cd /workspaces/zskills && ... && cd $WT && git push` with `git -C "$WT" push` (or subshell `( cd "$WT" && git push )`) so the first-cd target IS the operating root. Update `skills/fix-issues/SKILL.md` Phase 5/6 prose to recommend the `git -C <wt> ...` pattern explicitly; add a `tests/test-fix-issues-*.sh` unit that builds a `SPRINT_ID`-style string, runs the helper, and asserts the resulting path passes `[ -d ]`. Bump `skills/fix-issues/SKILL.md` `metadata.version` (skill subtree touched). `hooks/block-unsafe-project.sh.template` left unchanged (its first-cd-wins design is correct for the threat model it guards; the lesson goes upstream into caller discipline).

**Complexity:** S. **Action now:** /quickfix — skill-prose fix for Bug A (add `|| exit` discipline + worked-path-template note that SPRINT_ID already carries `sprint-`) + Bug B (recommend `git -C <wt> ...` over leading `cd <main>`) is a single SKILL.md edit + one test asserting the path-construction smoke check + one `metadata.version` bump. Both bugs are orchestrator/caller-discipline issues with the same locus (Phase 5/6 prose); hook unchanged. Single-purpose, bounded, no hook-internal changes required.

---

### #474 — briefing worktrees-status: subject-match breaks on PR-squash-merge `(#NNN)` suffix → every PR-mode worktree shows false NOT SAFE

**Labels:** bug | **Verdict:** NOT FIXED — `sed -n '1505,1514p' skills/briefing/scripts/briefing.py` shows `partition_commits_by_landing` doing literal `c['subject'] in main_subjects` equality (line 1509), and `git log main --format="%s" -n 500` populates `main_subjects` with the post-merge subjects (line 1537) that carry GitHub's default squash-merge `(#NNN)` suffix; the worktree branch's pre-merge subject lacks the suffix, so every PR-mode landed worktree falls into `unlanded` and the worktree is misreported as NOT SAFE.

**Problem.** `skills/briefing/scripts/briefing.py:1505-1514` (`partition_commits_by_landing`) classifies worktree commits as landed-vs-unlanded via literal subject equality against `main_subjects` (the set built at line 1537 from `git log main --format="%s"`). GitHub's default squash-merge rewrites the merged commit's subject to `<original subject> (#NNN)` on main; the worktree's pre-merge commit retains the unsuffixed subject. The string-equality check fails for every PR-mode worktree (the dominant zskills landing mode — recent main history shows `(#471)`, `(#467)`, `(#466)`, `(#465)`, `(#464)`, `(#463)`, `(#462)`, `(#461)` etc. uniformly), so `briefing worktrees-status` reports every successfully-merged PR-mode worktree as "NOT SAFE — unlanded commits." Per the `feedback_stale_worktrees_not_overlap.md` memory anchor, agents reading false NOT SAFE signals decline cleanup, compounding the existing dead-worktree pile-up. Test gap: `tests/test-briefing-parity.sh` smokes all 7 subcommands but no fixture exercises PR-squash-merged subject normalization.

**Fix outline.** Add a `_PR_SUFFIX_RE = re.compile(r'\s*\(#\d+\)\s*$')` module-level constant and a `_normalize_subject(s)` helper near `partition_commits_by_landing` in `skills/briefing/scripts/briefing.py`. Normalize on BOTH sides: change line 1537 to `main_subjects = {_normalize_subject(s) for s in main_log.split('\n')} if main_log else set()` and line 1509 to `if _normalize_subject(c['subject']) in main_subjects:`. Mirror to `.claude/skills/briefing/scripts/briefing.py`. Extend `tests/test-briefing-parity.sh` with a fixture: create a temp main with a `(#42)`-suffixed commit, create a worktree branch with the corresponding unsuffixed subject, assert `partition_commits_by_landing` returns the commit in `landed` not `unlanded` (or assert the rendered worktrees-status text shows SAFE TO REMOVE). Bump `skills/briefing/SKILL.md` `metadata.version` since the script lives under the skill subtree.

**Complexity:** S. **Action now:** /quickfix — regex + 2-line normalization at the two comparison sites + script mirror + 1 fixture test + 1 version bump. Single-purpose, mechanical, well-bounded; matches the issue body's recommended Option 1 (the patch-id alternative is heavier and unnecessary for the squash-suffix case).

---

### #480 — verify-response-validate.sh whitelist (Layer 3 of verifier-cannot-run defense) is bypassable by trivial paraphrase

**Labels:** bug | **Verdict:** NOT FIXED — `sed -n '29,37p' hooks/verify-response-validate.sh` confirms the 7-phrase `PATTERNS_STALLED` array anchored to literal Monitor/BashOutput terminology (`"let me wait for the monitor"`, `"tests are running. let me wait"`, `"monitor will signal"`, `"monitor to signal"`, `"still searching. let me wait"`, `"waiting on bashoutput"`, `"polling bashoutput"`). Plausible paraphrases that any genuinely-stalled verifier would emit ("I'll wait for the test suite to finish", "still running, will check back", "the impl agent is still running in background", "polling the long task") share no substring with the 7 entries and pass with exit 0. The check at line 60-67 is pure literal `[[ "$LAST_LINES" == *"$pattern"* ]]`, no regex/heuristic fallback. Test gap: `tests/test-verify-response-validate.sh` exists but per the issue body asserts only the 7 specific phrases — no paraphrase negative cases.

**Problem.** `hooks/verify-response-validate.sh:29-37` defines a 7-entry stalled-string whitelist matched as case-insensitive substrings against the last 10 lines of the verifier's response. Every entry is anchored to specific Monitor / BashOutput terminology from the original PR #175 stall pattern. A real-life stalled verifier emitting structurally identical content with paraphrased wording — "I'll wait for the tests to finish", "still running in background, will check back", "polling the long task" — passes the validator clean. Per CLAUDE.md `## Verifier-cannot-run rule`, Layer 3 is the universal failure-protocol primitive piped through at all 5 verifier-dispatch sites (/run-plan, /commit, /fix-issues, /do, /verify-changes); when its whitelist misses a real stalled phrasing, the orchestrator commits unverified work — the exact PR #175 incident the D'' architecture exists to prevent. Layer 0 (`inject-bash-timeout.sh` 600s extension) is the primary defense and moderates severity, but Layer 3 is the load-bearing safety net and a bypass here erodes the architecture's stated invariant.

**Fix outline.** Two complementary patches, both small. (a) Broaden `PATTERNS_STALLED` to a structural-pattern set rather than 7 terminology-specific strings: add entries for the "wait/still/poll + verb-object" co-occurrence class — `"still running"`, `"still waiting"`, `"will check back"`, `"check back later"`, `"in background"`, `"running in background"`, `"polling"`, `"in progress"`, `"still in progress"`, `"i'll wait"`, `"let me wait"` (the last two cover the "I'll wait for X" / "let me wait for Y" paraphrase class without requiring "monitor"). Substring match keeps it cheap and inspectable. (b) Extend `tests/test-verify-response-validate.sh` with paraphrase negative-case fixtures from the issue body (each `expect_fail` asserts exit 1): "I'll wait for the test suite to finish", "still running, will check back", "the impl agent is still running in background", "polling the long task", "the test command is still in progress". Keep all 7 existing positive cases. The issue body's "Alternative" (absence-of-action-completed signals heuristic) is judgment-class and would re-litigate Layer 3's design; defer to a separate decision if the broadened whitelist proves insufficient. No skill-subtree changes — `hooks/verify-response-validate.sh` is hook source, not skill source, so no `metadata.version` bump needed. Mirror to `.claude/hooks/verify-response-validate.sh` per managed-rule convention.

**Complexity:** S. **Action now:** /quickfix — ~10-entry whitelist extension in `hooks/verify-response-validate.sh` + 1-line mirror + 5 paraphrase negative-case fixtures appended to `tests/test-verify-response-validate.sh`. Single-purpose, mechanical, the issue body provides exact fixture text and recommended-entry list, and the alternative-heuristic option is explicitly out-of-scope as a separate judgment call. Matches the regex/whitelist-extension class called out as /quickfix-S in the sizing rubric.

---

### #475 — briefing worktrees-status: 500-commit cap on main_subjects causes false NOT SAFE for old worktrees (main now 637 commits)

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n "git log main" skills/briefing/scripts/briefing.py` shows `main_log = run('git log main --format="%s" -n 500', cwd=main_path)` at line 1564 (post-#474, was line 1538 pre-merge); `git rev-list --count main` in the sprint worktree reports **652** commits — already past the 500 cap and growing. Any worktree commit whose subject matched a main commit older than the most recent 500 falls into `unlanded` despite being fully landed.

**Problem.** `skills/briefing/scripts/briefing.py:1564` hardcodes `-n 500` on the `git log main --format="%s"` invocation that populates the `main_subjects` set consumed by `partition_commits_by_landing` (line 1509 area). With main at 652 commits today, the oldest ~152 commits' subjects are missing from the comparison set, and any worktree whose landed commits sit in that pre-cap window is misclassified as `unlanded` → worktrees-status renders false NOT SAFE. The bug compounds #474's squash-merge suffix bug — both feed the same `subject in main_subjects` lookup, and fixing one alone still leaves the other producing false NOT SAFE signals. The bug grows monotonically: every commit landed widens the unreachable window. Test gap: `tests/test-briefing-parity.sh` does not exercise a >500-commit main against an older worktree.

**Fix outline.** Drop the `-n 500` cap entirely: change line 1564 to `main_log = run('git log main --format="%s"', cwd=main_path)`. Per the issue body, 600+ subjects is ~30 KB — no memory concern, and the cost is one `git log` invocation that already streams. Mirror to `.claude/skills/briefing/scripts/briefing.py`. Extend `tests/test-briefing-parity.sh` (or a new fixture) to construct a synthetic main with >500 commits and assert a worktree commit matching a subject at position 600+ classifies as `landed`. Bump `skills/briefing/SKILL.md` `metadata.version`. (Alternative options — dynamic cap via `git rev-list --count main`, or `git cherry`-style patch-id matching — are strictly heavier and unnecessary; raising the cap to e.g. 5000 just defers the same bug to a later commit count.)

**Complexity:** S. **Action now:** /quickfix — single literal change (drop `-n 500`) + script mirror + 1 fixture test + 1 version bump. Single-purpose, mechanical, well-bounded; sibling fix to #474 touching the same file, builds on its (#NNN) normalization.

---

### #476 — briefing landed-pr-ready / landed-pr-needs-attention reflect stale `.landed` file, never query live PR state

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n 'gh pr view\|gh pr list' skills/briefing/scripts/briefing.py` returns zero hits (reproduction matches issue body); `skills/briefing/scripts/briefing.py:335-361` classifies worktrees into `landed-pr-ready` (status == `pr-ready`) and `landed-pr-needs-attention` (status in `pr-ci-failing` / `pr-failed` / `conflict`) purely from the `.landed` marker file content, with no GitHub API call anywhere in the briefing pipeline. Categories then drive Verify-mode output (line 1248 `pr_ready` filter, line 1258 `pr_attention` filter) and Report-mode summary counts (line 966-969) — all reading marker state as if it were live.

**Problem.** `.landed` markers are written once at landing time by `/commit pr` / `/land-pr` (status `pr-ready` when the PR is created and waiting on CI, or `pr-ci-failing` etc. on failure). After the PR's lifecycle continues on GitHub — CI passes, merge happens, or PR is closed without merge — the marker is never updated. `skills/briefing/scripts/briefing.py:335-361` reads the stale marker and renders the worktree as still-`pr-ready` or still-`pr-needs-attention`. Downstream: agents acting on `briefing current` output may attempt to extract/re-land a worktree whose PR is already MERGED (no-op fix-cycle waste), remove a worktree whose PR was CLOSED-unmerged (loses unlanded work), or treat a long-since-failed PR as still-CI-running. Per the user's memory anchor `feedback_stale_worktrees_not_overlap.md`, briefing is the canonical source of "dead vs. active overlap" determinations — stale-data-driven misclassification compounds the dead-worktree pile-up the anchor exists to discourage. Test gap: no fixture flips a `.landed` marker to `pr-ready` while the corresponding PR is closed-unmerged and asserts briefing surfaces the divergence.

**Fix outline.** Two-tier output as the issue body recommends. (a) For each `.landed`-marker-bearing worktree with status `pr-ready` / `pr-ci-failing` / `pr-failed` / `conflict`, optionally call `gh pr view <branch> --json state,mergeStateStatus,number` once per worktree (cache the result in-process to avoid hammering during a single briefing run; no persistent cache needed — briefing is short-lived). (b) Merge live state with marker state in the category-emit at `briefing.py:335-361`: if `state == "MERGED"` upgrade to a new `landed-pr-merged` category ("safe to remove — PR merged"); if `state == "CLOSED"` without merge downgrade to `landed-pr-abandoned` ("recover work before removing — PR closed unmerged"); if `state == "OPEN"` keep the marker-derived category. (c) Gate the API call behind a flag (`--verify-pr` or similar) so the cheap `.landed`-only path remains default for fast `briefing current` calls; the slower verified path runs on explicit opt-in or in `briefing verify` mode where authoritativeness matters more than speed. (d) Mirror to `.claude/skills/briefing/scripts/briefing.py`, extend `tests/test-briefing-parity.sh` with a fixture that stubs `gh pr view` to return MERGED and asserts the worktree categorizes as `landed-pr-merged` not `landed-pr-ready`. Bump `skills/briefing/SKILL.md` `metadata.version` (skill subtree). The "only MERGED is terminal-safe" simplification is viable as a smaller variant — sole new category `landed-pr-merged`, everything else stays marker-derived — but loses the closed-unmerged signal which is the more dangerous misclassification.

**Complexity:** S. **Action now:** /quickfix — add a single `gh pr view` lookup helper (~15 lines: branch → `state` / `mergeStateStatus`, in-process dict cache), 2 new category branches at lines 335-361, mirror the script, 1 fixture test with a `gh` stub, 1 `metadata.version` bump. Mechanical and bounded; the issue body's recommended approach is the simpler variant of the fix outline above. The "two-tier flag gate" decision is a minor design judgment (flag name + default), but doesn't escalate the change to /do scale — single SKILL.md script + one mirror + one test.

---

### #477 — fix-report SKILL.md:451 contains `Command: npm run test:all` in report-template prose (deny-list bypass via prose)

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n 'npm run test:all' skills/fix-report/SKILL.md` confirms line 451 (`- **Test Suite Status** — \`Command: npm run test:all\` + per-suite counts`) — a bullet with a code-span carrying the literal `npm run test:all`. No `<!-- allow-hardcoded: ... -->` marker is present above the bullet (lines 442-450 are plain prose with no marker). The literal IS in `tests/fixtures/forbidden-literals.txt` (the canonical deny-list source), so the scanner intends to catch it — but doesn't.

**Problem.** Two coupled gaps, both real. (a) **Authoring gap:** `skills/fix-report/SKILL.md:451` enumerates what the emitted Test Suite Status section should contain via a literal `Command: npm run test:all` in a code-span. Per CLAUDE.md `## Skill-file hardcode discipline` and PR #454's drift sweep, the canonical fix is to resolve via `$FULL_TEST_CMD` (placeholder in the template prose; the resolved value flows from `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` at runtime). Every consumer with a non-`npm`-based `testing.full_cmd` produces a fix-report whose Test Suite Status section embeds the wrong command string. (b) **Scanner-coverage gap:** the deny-list scanner's prose-imperative detection at `tests/test-skill-conformance.sh:1709-1711` matches only bullet/numbered lines that (i) contain a code-span AND (ii) START with an imperative verb (`Run|Execute|Invoke`) per the regex `(^|[.\;\:][[:space:]]+|\*\*)(Run|Execute|Invoke)[[:space:]]`. Line 451 satisfies (i) but fails (ii) — its sentence-start is "Test Suite Status", not Run/Execute/Invoke — so the scanner walks past it. The imperative-verb gate is the bypass surface, exactly as the issue body diagnoses. The issue is correctly flagged as low severity (functionally-correct report output for the dominant `npm`-based consumer), but the discipline value of #454 erodes with every drift literal that slips through.

**Fix outline.** Authoring fix (the productive option per the issue body's Option 1): replace `\`Command: npm run test:all\`` at SKILL.md:451 with `\`Command: $FULL_TEST_CMD\`` (placeholder; the emitter at runtime resolves via the canonical config-prelude). No fence-local source-script line needed because the literal is in markdown prose, not a bash fence — the emitter resolution happens in whichever step actually writes the FIX_REPORT.md output. Bump `skills/fix-report/SKILL.md` `metadata.version` (skill subtree touched). Mirror to `.claude/skills/fix-report/SKILL.md`. The scanner-coverage gap (b) is a separate, larger fix — extending the prose-imperative gate at `tests/test-skill-conformance.sh:1711` to also match descriptive-bullet lines (e.g. bullets with `**Bold Label** — ... \`<code-span>\` ...` pattern) requires care to avoid over-matching commentary; defer to a follow-up issue. The issue body's Option 2 (add allow-hardcoded marker) is the wrong escape hatch here — the literal is the antipattern being demonstrated, not an intentional report-template anchor, so the placeholder replacement is the right move per Option 1.

**Complexity:** S. **Action now:** /quickfix — single-line literal-to-placeholder swap in `skills/fix-report/SKILL.md:451` + `.claude/` mirror + 1 `metadata.version` bump. Single-purpose, mechanical, well-bounded, no judgment call (issue body's Option 1 is unambiguously the productive fix; Option 2 marker is the wrong escape hatch here). Scanner-coverage extension (gap b) intentionally deferred — it's a separate judgment-class decision about the imperative-verb gate's threshold and warrants its own issue + design pass.

---

### #504 — /briefing scheduling instructions reference invented CronCreate params (`install_command`, `schedule`) — `/briefing every` would fail tool validation

**Labels:** bug | **Verdict:** NOT FIXED — `sed -n '246,265p' skills/briefing/SKILL.md` confirms lines 252-253 ("`install_command`: `/briefing <base-mode-args>`" and "`schedule`: parsed from `<SCHEDULE>` (e.g., \"day at 9am\" → `0 9 * * *`)") and line 264 ("Filter for briefing-related crons (`install_command` starts with `/briefing`)") in the `stop` mode. Peer canonical pattern at `skills/fix-issues/SKILL.md:805` uses `CronCreate` with `prompt:` + `cron:` + `recurring:` per the documented schema; `skills/briefing/SKILL.md` is the only skill in the tree referencing these invented param names.

**Problem.** Three coupled defects in the `/briefing every <SCHEDULE>` scheduling prose, all in one section (lines 247-275). (a) **Invented param names:** `install_command` and `schedule` are not part of the CronCreate tool schema (which accepts `cron`, `prompt`, `recurring`, `durable`). An orchestrator literally following SKILL.md steps either rejects the call at tool-validation or silently substitutes — either way the documentation is wrong and trains agents on bogus parameter names. (b) **Bogus prompt shape:** even after correct substitution to `prompt:`, the documented value is `/briefing <base-mode-args>` (bare slash command) rather than the CLAUDE.md `## Cron-fired prompts` rule's canonical `Run /briefing <base-mode-args>` form that every peer skill uses (`/fix-issues`, `/qe-audit`, `/run-plan`, `/do`). `/briefing` doesn't set `disable-model-invocation: true` so the slash form would still route via the slash runtime, but it bypasses the documented post-`/clear` inline-SKILL.md-reading fallback that all peers follow. (c) **`stop` mode filter mismatch:** line 264's "Filter for briefing-related crons (`install_command` starts with `/briefing`)" is doubly wrong — the field is `prompt` (per CronList schema, mirroring CronCreate), and the value to match-against is `Run /briefing` per the canonical pattern. Also no `:03/:09` offset on time-based schedules (peer pattern per CLAUDE.md avoid-:00/:30 rule). No test coverage: `tests/test-briefing-parity.sh` has zero assertions on `every`/`stop`/`next` cron-management modes (verified by grep — file scans modes but exercises none of the schedule flow).

**Fix outline.** Replace SKILL.md:252-253 with the canonical three-line block: `cron:` (parsed from `<SCHEDULE>`, with `:03/:09` offsets on hour-based times — e.g. `9am` → `3 9 * * *` not `0 9 * * *`), `prompt: \`Run /briefing <base-mode-args>\``, `recurring: \`true\``. Update SKILL.md:264 `stop`-mode filter prose to "Filter for briefing-related crons (`prompt` starts with `Run /briefing`)". Bump `skills/briefing/SKILL.md` `metadata.version` (`2026.05.20+364df1` → recomputed via `scripts/skill-content-hash.sh`). Mirror to `.claude/skills/briefing/SKILL.md`. Test-gap (separate, larger fix): adding actual schedule-flow coverage to `tests/test-briefing-parity.sh` requires mocking CronCreate/CronList and would expand test scope materially; defer to a follow-up issue.

**Complexity:** S. **Action now:** /quickfix — single skill-prose section edit (4 lines changed across lines 252-264 of one file) + `.claude/` mirror + 1 `metadata.version` bump. Mechanical, well-bounded, no judgment call (canonical pattern at `skills/fix-issues/SKILL.md:805` is unambiguous; cron-fired-prompts rule in CLAUDE.md is the authoritative spec for the `Run /<skill>` prefix). Sized S not /quickfix-trivial because three coordinated edits touch one file (params, prompt shape, stop-filter), not a single one-line typo fix. Test-gap deferred per the per-issue scope discipline — would warrant its own /do pr or /draft-plan pass.

---

### #505 — /update-zskills install: `block-bad-cron.sh` (#456) and `block-main-edits.sh` (#308) missing from SKILL.md install list — fresh installs lack documented hook protections

**Labels:** bug | **Verdict:** NOT FIXED — `ls hooks/block-bad-cron.sh hooks/block-main-edits.sh` confirms BOTH files exist on main (source-of-truth present); `grep -n 'block-bad-cron\|block-main-edits' skills/update-zskills/SKILL.md` returns only line 1212 (a narrative reference inside Step C's session-init-only `settings.json` past-failure note), with no entry in the hook-copy bullet list at SKILL.md:1068-1101 OR in the canonical-triples table at SKILL.md:1191-1199. A fresh consumer running `/update-zskills install` follows that prose-driven loop and copies only the hooks named there — both protections are silently absent from the install. The repo's own `.claude/settings.json` does wire both (validating their canonical zskills-owned status), proving the omission is an authoring gap in SKILL.md, not a question of whether they belong.

**Problem.** Two coupled SKILL.md authoring gaps in `skills/update-zskills/SKILL.md` Step C ("Fill hook + agent gaps"). (a) The hook-copy bullet list at lines 1068-1101 enumerates `block-unsafe-project.sh.template`, `block-unsafe-generic.sh`, `block-agents.sh.template`, `warn-config-drift.sh`, `inject-bash-timeout.sh`, `verify-response-validate.sh`, `block-stale-skill-version.sh` — but neither `block-bad-cron.sh` (added by PR #456 at 06:18 UTC 2026-05-20, PreToolUse:CronCreate matcher, guards against TZ-confusion one-shot cron registration that #460 documented) nor `block-main-edits.sh` (added per issue #308, PreToolUse:Edit|Write|NotebookEdit matcher, gates against agents bypassing `main_protected: true` via direct file edits without committing). (b) The canonical-triples table at lines 1191-1199 — explicitly documented at line 1188 as the "single source of truth — anything not in this table is foreign and preserved untouched" — also omits both rows (and their matchers `CronCreate` / `Edit|Write|NotebookEdit`). Consequence: every fresh consumer install OR upgrade since PR #456 (today) and #308 lacks both hook protections — the consumer's `main_protected` config has no Edit/Write/NotebookEdit gate, and CronCreate calls with TZ-confusion errors register silently. The narrative at SKILL.md:1212 explicitly cites PR #456 — proving the author knew of the hook but updated only the past-failure prose, not the install machinery. Test gap: `tests/test-update-zskills*.sh` validates per-named-hook copy logic, not full-coverage hook enumeration; a new hook added to `hooks/*.sh` does not auto-fail conformance until SKILL.md is hand-updated.

**Fix outline.** Authoring fix in `skills/update-zskills/SKILL.md`. (a) Add two new bullets to the Step C copy list (lines 1068-1101) for `block-bad-cron.sh` and `block-main-edits.sh` — both copy-as-is, no template-render path needed (neither carries `{{...}}` placeholders; both read config at runtime via the same bash-regex idiom as siblings). Suggested grouping: extend the existing "For `block-unsafe-generic.sh`, `block-agents.sh.template`, `warn-config-drift.sh`: copy as-is..." bullet at lines 1074-1076 to also name both new hooks, OR add a sibling bullet immediately below it for symmetry. (b) Add two new rows to the canonical-triples table at lines 1191-1199 with their matchers: `PreToolUse | CronCreate | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-bad-cron.sh"` and `PreToolUse | Edit|Write|NotebookEdit | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-main-edits.sh"`. Update the "All 7 rows..." sentinel at line 1201 to "All 9 rows..." accordingly. (c) Mirror SKILL.md to `.claude/skills/update-zskills/SKILL.md`. (d) Bump `skills/update-zskills/SKILL.md` `metadata.version` (skill subtree touched). The deferred test-gap fix (issue body's "Test gap" section — enumerate `hooks/*.sh` + `hooks/*.template` and assert SKILL.md names each) is a separate, larger conformance-test design pass; defer to follow-up. Risk profile is low — both hooks are already source-resident with verified `.claude/settings.json` wiring in this repo, so the install-loop change is purely additive (no removal/rename of existing behavior). The session-init-only caveat at SKILL.md:1206-1218 (per #460) already covers in-flight session restart messaging and needs no edit; the install-list addition just ensures fresh consumers GET the hook to begin with.

**Complexity:** S. **Action now:** /quickfix — two bullet additions in SKILL.md Step C copy list + two row additions in the canonical-triples table + sentinel count update ("7 rows" → "9 rows") + `.claude/` mirror + 1 `metadata.version` bump. Single-purpose, mechanical, well-bounded; no test changes required for the authoring fix (the deferred conformance-test redesign is correctly scoped out as follow-up); no judgment call (both hooks exist in source and are validated as canonical via this repo's own `.claude/settings.json` wiring). Sibling discipline class to #477 — drift-class authoring gap, single SKILL.md edit + mirror + version bump.

---

### #506 — migrate-paths.sh exits 1 with partial state (rerender done, config unchanged) on compact-JSON input — violates #394's no-partial-state invariant

**Labels:** bug | **Verdict:** NOT FIXED — `sed -n '438,470p' skills/update-zskills/scripts/migrate-paths.sh` confirms Step 2.5 copies `block-unsafe-project.sh.template` → `.claude/hooks/block-unsafe-project.sh` (and chmods +x) BEFORE Step 3's atomic config write at line 472. `sed -n '710,720p'` confirms the awk pattern at line 714 (`/^[[:space:]]*\}[[:space:]]*$/`) requires the outer closing brace on its own line — a compact one-line JSON like `{"project_name":"test"}` fails the regex, awk exits 2, Step 3 aborts with "FAIL: cannot locate outer closing brace", and the consumer is left with the hook file mutated and config unchanged. Reproduction in the issue body is concrete and reliable.

**Problem.** The #394 invariant (documented in the file header at lines 4-10: "idempotency lock writes LAST … config write is atomic-or-skipped, file moves are atomic-per-file") is structurally violated by Step 2.5's intentional pre-Step-3 hook copy. The header at lines 16-19 documents the ordering tradeoff ("Trigger --rerender BEFORE any moves so the broadened recursive-delete fence is in place"), but the assumption that the rerender is a "safe" mutation — because it only touches `.claude/hooks/block-unsafe-project.sh` — overlooks that ANY pre-Step-3 mutation creates partial state when Step 3 fails. The awk regex at line 714 is the proximate trigger but the architectural gap is that Step 2.5 mutates filesystem state before Step 3's config-parse validates the input is well-formed. On compact-JSON consumers, the script exits 1 with the hook file already updated (no rollback), the config unchanged, no manifest written — and the re-run path is broken because the hook is already at the new state. The bug is silent in the sense that the error message points at "outer closing brace" without mentioning the orphaned hook copy.

**Fix outline.** Issue body's Option 2 ("pre-validate config before Step 2.5 — fail-loud before any state mutation if the config can't be parsed") is the cleanest fix and aligns with #394's spirit ("don't mutate state until you know the config write will succeed"). Concretely: extract the awk-block-locator logic from `write_output_block` into a pre-flight validation function that runs at Step 2 (between detection and Step 2.5), parses the existing config to verify the outer-`}` regex matches, and exits 1 with a clear "config format unsupported: outer closing brace not on its own line" error BEFORE any hook copy. The hook copy in Step 2.5 then only runs on a known-parseable config. Issue body's Option 1 (relax awk to accept compact JSON) is a complementary fix that should also land — match `\}[[:space:]]*$` (drop the leading-whitespace anchor) and add unit fixtures for both compact and multi-line. Option 3 (rollback Step 2.5 on Step 3 failure via tempfile-save) is heavier and only partially addresses the structural issue — better to never mutate prematurely than to engineer rollback. The cleanest landing: BOTH Option 1 (regex relax + fixtures) AND Option 2 (pre-validate) — they're complementary not alternative. Add test fixtures for compact + multi-line + missing-outer-`}` formats in the migrate-paths test file (whichever `tests/test-*.sh` covers migrate-paths.sh — likely `tests/test-update-zskills-migration.sh` or sibling). Script-only change; SKILL.md prose unchanged so no `metadata.version` bump needed unless the canonical-config-prelude reference is touched.

**Complexity:** S. **Action now:** /quickfix — bounded mechanical change (awk regex relax + new pre-validate function + 2-3 fixture files). The awk relax is one-line, the pre-validate function is a ~15-line extraction of existing logic with an early-exit, and the fixtures are trivial. Single script (`skills/update-zskills/scripts/migrate-paths.sh`), single test file, no cross-cutting decisions. The two-fix combination (Option 1 + Option 2) is the right scope — Option 1 alone leaves the structural gap (other parse failures could still partial-state); Option 2 alone leaves canonical compact-JSON consumers needing pre-format. Both together close the hole properly without escalating to /do scale. Sized S not /quickfix-trivial because Option 2 introduces a new function with its own contract (when to call, what to validate, what error format) — a small but real design decision, not a one-line literal swap.

---

### #514 — Dashboard /api/state median latency ~6s (vs /api/work-state at ~2s) — user-visible lag due to collect_snapshot() cost

**Labels:** bug | **Verdict:** NOT FIXED — `grep -n "collect_snapshot\|def _handle_state\|def _handle_work_state_get" skills/zskills-dashboard/scripts/zskills_monitor/server.py` confirms `_handle_state` at server.py:777 calls `_collect.collect_snapshot(main_root, pre_resolved=True)` synchronously on every GET (lines 788-793), while `_handle_work_state_get` at server.py:1004 reads one JSON file under a single lock. `grep -n "def collect_snapshot\|_scan_tracking_markers\|_scan_git_history\|_list_worktrees\|_list_branches\|parse_plan\|parse_report\|list_issues" skills/zskills-dashboard/scripts/zskills_monitor/collect.py` confirms `collect_snapshot` at line 1580 sequentially invokes: `parse_plan` per `.md` in plans_dir (1619-1636), `parse_report` per plan (1626), `_resolve_landing_mode` per plan (1624), `_read_state_file` (1639), `list_issues` (1648 — already 60s-cached), `_list_worktrees` (1652 — subprocess `git worktree list`), `_list_branches` (1653 — subprocess `git for-each-ref`), `_scan_tracking_markers` (1659 — `iterdir` over `.zskills/tracking/` + every subdir + `_parse_marker_file` per marker), `_extract_pr_numbers_from_markers` (1660 — second pass over tracking dir), `_scan_git_history` (1661 — subprocess `git log --since=72.hours.ago --max-count=200`). `gh issue list` is NOT the bottleneck (60s TTL cache at collect.py:1077-1106 absorbs 96%+ of polls). Per the issue body's measured 4s median server-side latency, the dominant costs are the per-poll subprocess fan-out (3 git invocations + `git for-each-ref` walks every branch) and the filesystem scan over `.zskills/tracking/$PIPELINE_ID/` subtrees (which can hold thousands of markers across multi-month repos). Test gap: `tests/test-zskills-dashboard-*.sh` exercises `_handle_state` for correctness but has no latency assertion or fixture sizing the tracking-marker tree to realistic counts.

**Problem.** `_handle_state` synchronously rebuilds the full snapshot on every 2s client poll, with no cache layer. The work falls into three cost buckets per the source: (1) **3 git subprocesses** — `_list_worktrees`, `_list_branches`, `_scan_git_history` — each forks a `git` process, with the latter two reading hundreds of refs/commits; these don't change between most polls. (2) **Tracking-marker filesystem scan** at `_scan_tracking_markers` (collect.py:665-784) — `iterdir` over `.zskills/tracking/`, descend into every pipeline subdir, `_parse_marker_file` per `requires.*`/`fulfilled.*`/`step.*` basename; this scales with sprint volume and never gets pruned in long-lived repos. (3) **Plans+reports parse fan-out** — every `*.md` in `plans/` is parsed via `parse_plan` + `parse_report` + `_resolve_landing_mode` on every poll, even though plan files change once per /run-plan phase tick (minutes, not seconds). The result is structural mismatch with the client cadence: `/api/work-state` is 1-file 1-lock cheap, `/api/state` is dozens-of-syscalls + 3-subprocess heavy, both polled at 2s. User-visible lag (sprint state changes take 2-6s to render vs /api/work-state's instant updates) is the surfaced symptom; deeper consequence is dashboard scaling — every additional landed sprint widens the tracking-marker tree and lengthens `git log`/`for-each-ref` output, so latency grows monotonically with repo age. The issue body's measured 22% delivery rate vs work-state's 89% means **78% of /api/state polls drop on the floor** (client is mid-fetch when next interval fires) — the dashboard's "watch sprints land" UX is structurally degraded.

**Fix outline.** The cleanest single-PR scope is the issue body's **Option 1 (cache the cheap-to-recompute, expensive-to-fetch parts of `collect_snapshot` with a short TTL)** specialized to a **process-local snapshot cache with per-subsystem TTLs** rather than a single global TTL. Concretely: introduce a module-level `_SNAPSHOT_CACHE` in collect.py keyed by `(main_root, kind)` with TTLs tuned to each subsystem's natural change frequency — `worktrees`/`branches` ~5s (git subprocesses, rarely change between human-scale actions); `git_history` ~10s (new commits land at human cadence, not 2Hz); `plans+reports` ~3s (plan files change on phase ticks, mtime-gated would be even better but TTL is simpler); `tracking_markers` ~3s (marker writes happen on /run-plan boundaries). State-file read (1639) and `list_issues` (1648) keep their current path (state file is the live-source-of-truth for queue annotations and must not be stale, `list_issues` already 60s-cached). The cache value is the parsed result of each helper, so a fresh `collect_snapshot` call assembles from cached pieces + always-fresh state. Expected effect: 2s client polls hit cache for everything except the state-file merge, dropping median server time from ~4s toward `/api/work-state`'s 2-file-stat baseline. Mirror to `.claude/skills/zskills-dashboard/scripts/zskills_monitor/collect.py`. Bump `skills/zskills-dashboard/SKILL.md` `metadata.version` (skill subtree). Tests: extend `tests/test-zskills-dashboard-*.sh` with (a) latency-budget assertion on a fixture repo with 200 tracking markers + 20 plans + 50 branches (asserts second-poll-within-TTL < some millisecond budget), (b) invalidation correctness — bumping a marker mtime causes the next poll to re-scan that subsystem. The issue body's other options are reasonable alternatives but worse-scoped: Option 2 (endpoint split) doubles the API surface and forces client-side coordination; Option 3 (drop client cadence) is a one-line app.js patch that papers over the structural cost without reducing server load, and trains away the dashboard's responsiveness ceiling; Option 4 (background pre-compute thread) introduces threading into a stdlib-only server and creates a cache-staleness window that's harder to bound than per-subsystem TTLs. Per-subsystem TTL caching dominates: it keeps the API surface stable, the cost reduction is structural (not just throttled), and the implementation is contained in collect.py with no server.py changes.

**Complexity:** M. **Action now:** /do pr — multi-helper refactor in `collect.py` (introduce cache dict + decorator-or-helper pattern around 4 helpers + invalidation logic), 1 mirror, 1 `metadata.version` bump, 2 new fixture-driven tests with realistic counts. Sized M not S because (a) the cache design has real judgment — per-subsystem TTLs vs single TTL vs mtime-based, which subsystems to include — and the issue body's option 1 is the right family but doesn't pre-specify TTL values; (b) the fixture-sizing test is non-trivial (need to construct a repo with 200 tracking markers + 20 plans to exercise the cost surface meaningfully); (c) ~5 collect.py callsites change, not just one. The dashboard skill surface is also larger than briefing's — a sloppy cache invalidation can show stale sprint state (the opposite of the symptom this PR is fixing), so the test coverage is load-bearing. Not /draft-plan scale because the design pattern (per-subsystem TTL cache) is well-known and the scope is one file + one test file; no integration-points or hook interactions. The cheap-mitigation option (3) is genuinely viable as a one-line `POLL_INTERVAL_MS_STATE = 5000` follow-up if /do pr is contention-blocked, but it's a workaround not a fix — file as separate /quickfix only if M-scoped work is deferred.

---

### #513 — Hook-bypass closure cycle: 9+ PRs in 10 days reactively patching same block-unsafe surface — missing property-style enumeration test

**Labels:** bug | **Verdict:** NOT FIXED — `gh pr list --state merged --search "block-unsafe OR force-prefix OR refspec OR wrapper" --limit 100` confirms the cycle (11 merged PRs across #73, #87, #195, #197, #306, #413, #417, #434, #435, #465, #486 — the most recent two landing 09:01 and 14:11 UTC on 2026-05-20, with #486's title literally "close +main bypasses surviving #465 (Closes #470)"). `grep -nE "expect_(deny|allow)" tests/test-hooks.sh | grep -i "main\|master" | wc -l` returns 20 — each one a hand-added positive assertion for a specific bypass form discovered after-the-fact (issue tags `#392`, `#457`, `#470` are explicit in the test labels at lines 382-406). No enumerative loop: `grep -nE "for .* in.*(bash -c|sh -c|eval|\\+main|refs/heads)" tests/test-hooks*.sh` returns zero hits. The bypass surface is enumerated by hand, one PR at a time. `gh issue list --state all --search "property test enumerate combinations hook"` returns zero hits — this issue is the first to name the fix shape.

**Problem.** Two coupled gaps, the second causing the first. (a) **Combinatorial coverage gap:** `tests/test-hooks.sh` lines 375-406 enumerate ~20 specific push-to-main forms — but the bypass space is the cartesian product `{wrapper: bash -c, sh -c, eval, none} × {ref-prefix: refs/heads/, none} × {force-prefix: +, none} × {refspec-form: bare, feat:X, HEAD:X, :X (deletion), localref:X} × {quote-style: ', ", none}` ≈ 4×2×2×5×3 = 240 cases — and only ~20 hand-picked points are covered. The hook normalization at `hooks/block-unsafe-generic.sh:612-633` strips them sequentially (`${X##*:}` → quote strip → `${X#+}` → `${X#refs/heads/}`); the project hook at `block-unsafe-project.sh.template:1037-1051` does the equivalent via regex `[+:]?(refs/heads/)?(main|master)`. Both encodings ARE in principle complete for the current matrix — but neither is property-tested, so the closure was reached by 11 reactive PRs over 24 days and no agent (or human) can be confident the matrix is fully covered without writing the enumeration. (b) **Process anti-pattern:** the cycle is the textbook "patched around, never propagated to the right defense" failure from CLAUDE.md `## Memory anchors are agent-local notes` — each PR adds a single positive assertion for the variant the agent found, never the combinatorial cap that would have caught the next agent's variant at CI time. The issue body's "11 fires in 24 days" math is correct (titles `4 remaining` #306, `surviving #465` #486 self-flag the closure-incompleteness). PR #486 (today) being the most recent — and being driven by issue #470 filed only ~10 hours after #465 landed — is the canary that the cycle is structurally not slowing down.

**Fix outline.** Property-style enumeration test in `tests/test-hooks.sh` (or a sibling `tests/test-hooks-bypass-matrix.sh`). Concrete shape:

```
for wrapper in "" "bash -c " "sh -c " "eval "; do
  for refprefix in "" "refs/heads/"; do
    for forceprefix in "" "+"; do
      for refspec_form in "$DEST" "feat:$DEST" "HEAD:$DEST" "localref:$DEST" ":$DEST"; do
        for quote in '' "'" '"'; do
          cmd="${wrapper}${quote:+$quote}git push origin ${forceprefix}${refprefix}${refspec_form}${quote:+$quote}"
          # for DEST in main, master → expect_deny under BLOCK_MAIN_PUSH=1
          # for DEST in feat/x → expect_allow
        done
      done
    done
  done
done
```

Run against BOTH `hooks/block-unsafe-generic.sh` AND `hooks/block-unsafe-project.sh.template` (rendered via `update-zskills`'s template render path with project-config defaults). Mirror to `.claude/hooks/` parity check (`tests/test-hooks-mirror-parity.sh` currently has 0 push assertions — confirmed via `grep`). ~240 cases × 2 hooks × 2 destinations (main vs feat) = ~960 expect calls; at the existing `expect_deny` per-case ~10ms cost that's ~10s total — cheap. Critical decision: this is **test-only, not a deny refactor.** The current hook normalization already covers the matrix in principle (per the #470 fix landing the `refs/heads/` strip); the missing thing is the test that proves it and catches future drift. Adding the property test is purely additive — no hook changes, no `metadata.version` bumps (no skill subtree touched). The expected first run may discover 1-2 currently-uncovered points (e.g., `sh -c` wrapper combined with `+refs/heads/main` — never explicitly tested) which would land alongside the enumeration in the same PR via a small hook-side fix. The wrapper-recursion axis touches the `extract_cd_target` recursion from #427 (already landed in #435) so `bash -c 'bash -c "git push origin +main"'` is already covered structurally; the test just needs to enumerate one wrapper-depth=1 layer to assert closure. Allow-list discipline: the matrix asserts BOTH deny (for main/master destinations) AND allow (for feature-branch destinations) — the latter is critical because over-broad regex changes during the cycle have caused symmetric false-positives (e.g., legitimate `feat:main-branch-rename` style names — escape with anchors). Defer: a separate "negative-allow matrix" expanding the feat-branch allow side to 100+ feature-branch-name variants is out of scope; the deny matrix is the primary fix.

**Complexity:** M. **Action now:** /do pr — test-only addition with non-trivial design surface. Sized M not S because: (1) the matrix dimensions (5 axes, 240 cases) need careful enumeration to avoid both over-coverage (impossible combinations) and under-coverage (forgotten axes — e.g., `--force-with-lease` flag was missed in the original enumeration); (2) the project-hook rendered-template test path requires invoking `update-zskills`'s template render machinery, not just sourcing the template; (3) the parity-check tier (mirror to `.claude/hooks/` per `tests/test-hooks-mirror-parity.sh`) needs careful selection of which subset of the 240 cases runs at parity-time vs at primary-test-time to keep parity-test runtime bounded; (4) any test failures during the initial run surface real hook gaps that need to land in the same PR (additive fix-class). Not /draft-plan scale because the design surface is bounded (one test file, one or two new helper functions, no hook surgery beyond closing any gaps the matrix surfaces); not /quickfix scale because the enumeration + dimension-choice decisions are genuinely judgment-class, not mechanical. **Fix shape: test-only enumeration (NOT structural deny refactor).** The hook normalization is structurally sound per the cumulative landings; the gap is the absence of the property-test that proves it.

---

### #518 — Silent miscategorization: .landed `status: failed` / `direct-push-failed` / `direct-verify-failed` not recognized by briefing.py + /fix-report readers

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `.landed` writers emit failure-class statuses (`failed`, `direct-push-failed`, `direct-verify-failed`) per failure-protocol.md:118 and direct.md:80/112, but readers (`briefing.py:397-461`, `fix-report/SKILL.md:161`) whitelist only success-class statuses (`full`, `landed`, `partial`, `pr-ready`, `pr-ci-failing`, `pr-failed`, `conflict`, `pr-state-unknown`). Failure-class markers fall through to mtime-bucket "old worktree" — defeating the whole point of the failure statuses (per failure-protocol.md:125).

**Fix outline.** Extend the two reader whitelists to recognize the three failure statuses and route them to a "needs attention" bucket: (a) `briefing.py:430` add `failed`/`direct-push-failed`/`direct-verify-failed` to the set and surface in the `landed-pr-needs-attention` summary; (b) `fix-report/SKILL.md:161` extend the documented closed status set + status table. Add a small conformance test (`tests/test-landed-status-vocabulary.sh`) listing every writer-emitted status and asserting each appears in the reader whitelists. Companion dormant `server.py:_resolve_paths` reports_dir omission noted in body but out of scope here.

**Complexity:** S (2-file edit + 1 small test). **Action now:** /do pr — extend the reader whitelists in `briefing.py:430` and `fix-report/SKILL.md:161` to include the three failure-class statuses; add `tests/test-landed-status-vocabulary.sh` asserting every writer status appears in every reader whitelist.

---

### #517 — Test assertion fidelity: 3 tests pass for the wrong reason

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** Three tests assert proxies, not the behavior they claim to test. Each can be silently bypassed by a real regression: (1) `tests/test-briefing-parity.sh:65-77` asserts `exit_code -eq 0 AND (non-empty stdout OR empty stdout)` — the second clause is a tautology; (2) `tests/test_zskills_monitor_server.sh:341-359` validates `/api/plan/<slug>` activity[] filtering by checking presence-only, no second pipeline seeded to assert EXCLUSION (the #473 fix would silently regress); (3) `tests/test-skill-conformance.sh:535-541` uses whole-file `grep -E` for the `subagent_type: "implementer"` pin so a comment mentioning it satisfies the assertion even if the actual dispatch site has been demoted.

**Fix outline.** Per body's fix sketches: (1) assert specific expected content per subcommand and drop the OR-empty branch; (2) seed a second pipeline `run-other-002` and assert EXCLUSION from `/api/plan/sample-plan` activity[]; (3) make `check_in_file` location-aware or add structured dispatch-site detection so the literal must appear in an Agent/dispatch context block, not anywhere in the file.

**Complexity:** S (3 test files; each fix is mechanical and ~15 lines). **Action now:** /do pr — rewrite the three assertions per the body's fix sketches; add a fixture for #2 (`run-other-002`) and a structured-dispatch-site check or near-Agent locality grep for #3.

---

### #516 — Silent commit loss: `/briefing worktrees-status` + `/cleanup-merged` treat PR=MERGED as proof of branch-on-main without ahead-count

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** Two classifiers — `briefing.py:441-461` `format_worktrees_status` and `cleanup-merged/SKILL.md` Rule 3 (line 358) plus Phase 5 default-mode path (270-310) — short-circuit on `gh pr view state=MERGED` and classify as SAFE_TO_REMOVE / REMOVE without checking `git rev-list --count $MAIN_BRANCH..$branch`. `gh pr view` is sticky after merge, so a worktree with post-merge commits on its feature branch is silently misclassified; the subsequent `git worktree remove` + `git branch -D` reaps the post-merge commits.

**Fix outline.** Add an ahead-count gate in BOTH surfaces BEFORE classifying as SAFE_TO_REMOVE/REMOVE. If `ahead > 0`, downgrade the category to `landed-pr-merged-but-diverged` (or similar) with reason `PR merged but branch has N commits not on main — investigate`. Same fix shape in both files. Add tests that simulate post-merge commits and assert NOT_SAFE_TO_REMOVE.

**Complexity:** M (2-file fix + new tests; data-loss-class so paired regression tests are mandatory). **Action now:** /do pr — add `git rev-list --count $MAIN_BRANCH..$branch` gate in `briefing.py:441` and `cleanup-merged/SKILL.md` Rule 3 + Phase 5 (270-310); add regression tests (`tests/test-briefing-worktrees-merged-diverged.sh`, `tests/test-cleanup-merged-ahead-gate.sh`) that seed post-merge commits and assert NOT_SAFE_TO_REMOVE.


---

### #538 — Missing tests/test-skills-mirror-parity.sh — skills/ ↔ .claude/skills/ divergence ships silently

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `tests/test-hooks-mirror-parity.sh` enforces byte-equality between `hooks/` and `.claude/hooks/` (model from #390 closure); no equivalent test exists for `skills/` ↔ `.claude/skills/`. A developer editing source skills and forgetting to mirror leaves CI green while Claude Code reads the stale `.claude/skills/<name>/SKILL.md` at runtime. The conformance gate (`test-skill-conformance.sh` `check_in_file ".claude/skills/..."`) is itself the bypass surface — it asserts against the stale text and passes.

**Fix outline.** Add `tests/test-skills-mirror-parity.sh` modeled on the hooks variant. Multi-source-root: compare `skills/X` → `.claude/skills/X` for every X under `skills/`, AND `block-diagram/X` → `.claude/skills/X` for every X under `block-diagram/`. Excess names in `.claude/skills/` not appearing in either source root → allow-listed (e.g., `playwright-cli`, `social-seo`) or fail-loud. Exclude `__pycache__` and `*.pyc`. Register in `tests/run-all.sh`.

**Complexity:** S (30-50 LOC test + 1 line in run-all.sh; no skill SKILL.md edits → no version bumps). **Action now:** /do pr — add `tests/test-skills-mirror-parity.sh` with multi-source-root byte-equality + documented whitelist; register in `tests/run-all.sh`.

---

### #537 — /do Phase 4 step 2 prose instructs `git stash -u` which hooks/block-unsafe-generic.sh denies

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `skills/do/SKILL.md:822-832` (Phase 4 step 2, Path B worktree cherry-pick landing) instructs `git stash -u` + `git stash pop`. `hooks/block-unsafe-generic.sh:387-388` denies bare stash + every stash write subcommand (`stash -u`, `stash push`, `stash save`). The agent following documented prose hits hook deny and gets stuck. The correct pattern is already encoded in `skills/commit/modes/land.md:26-27`: try-without-stash + let `git cherry-pick` refuse on overlap.

**Fix outline.** Replace `/do` SKILL.md Phase 4 step 2 prose with EITHER (Option 1) a dispatch to `/commit land` via the Skill tool — single source of truth, future fixes propagate — OR (Option 2) inline-mirror the `land.md` try-without-stash pattern verbatim. Option 1 is structurally cleaner. Bump `/do` SKILL.md `metadata.version` per skill-versioning discipline and mirror source → `.claude/skills/do/SKILL.md`.

**Complexity:** S (one prose block edit on `/do` SKILL.md + version bump + mirror; ~10-20 LOC). **Action now:** /do pr — replace `skills/do/SKILL.md:820-835` Phase 4 step 2 stash-based prose with a `/commit land` Skill-tool dispatch (preferred) or inline-mirror of `land.md:26-32` try-without-stash pattern; bump version + mirror.

---

### #536 — /commit test runs bypass canonical $TEST_OUT capture pattern

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** CLAUDE.md `## Tests` mandates the canonical `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; $FULL_TEST_CMD > "$TEST_OUT/.test-results.txt" 2>&1` capture pattern. Every test-running skill (`/quickfix`, `/investigate`, `/run-plan`, `/fix-issues`) implements it. `/commit` SKILL.md:272-278 (Phase 5 step 2) and `/commit modes/land.md:40-50` (Phase 7 step 5 post-cherry-pick gate) invoke `$FULL_TEST_CMD` raw — output dumps to terminal, scrolls past on long suites, agent re-runs to inspect (CLAUDE.md explicitly warns against). `land.md` is worse because test failures land mid-cherry-pick with no captured artifact for diagnosis.

**Fix outline.** Replace the raw `$FULL_TEST_CMD` invocations at the two sites with the canonical capture idiom. Add a "if tests fail, read `$TEST_OUT/.test-results.txt`" instruction. Pattern is already in CLAUDE.md and 4 peer skills. Bump `/commit` SKILL.md `metadata.version` (SKILL.md is edited; `modes/land.md` is a referenced file inside the skill dir so it's part of the content-hash projection). Mirror to `.claude/skills/commit/`.

**Complexity:** S (~5-line idiom per site + 1-2 fallback lines + version bump + mirror). **Action now:** /do pr — replace raw `$FULL_TEST_CMD` at `skills/commit/SKILL.md:272-278` and `skills/commit/modes/land.md:40-50` with the canonical `$TEST_OUT` capture idiom + read-on-failure instruction; bump version + mirror.

