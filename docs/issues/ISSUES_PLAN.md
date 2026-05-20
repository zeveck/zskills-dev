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
