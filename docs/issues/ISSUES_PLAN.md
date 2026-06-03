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


---

### #540 — test-create-worktree.sh case 7 + case 16 fail intermittently under bash tests/run-all.sh

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `tests/test-create-worktree.sh` cases trip intermittently under `bash tests/run-all.sh` (different cases under different orderings) but pass 26/26 in isolation. Reproduced in sprint `sprint-20260521-045250-sprint`: case 7 in #538's worktree (`fatal: unknown error occurred while reading the configuration files`), case 16 in #537's worktree (`fatal: Reference directory conflict: refs/heads/plans/`). Origin/main suite passes cleanly on fresh-clone CI. Bug is shared env-state leak from earlier suite tests (`GIT_CONFIG_GLOBAL`, `refs/heads/<prefix>` lingering refs, possibly /tmp state).

**Fix outline.** Path 1 (per-case env hermeticity): wrap each test case in a subshell with hermetic env (`GIT_CONFIG_GLOBAL`/`XDG_CONFIG_HOME`/`HOME` set to a per-case tmp dir; cleanup `refs/heads/<prefix>` under the test repo before/after). Path 2 (suite pre-cleanup): explicit cleanup step in `tests/run-all.sh` before `test-create-worktree.sh`. Path 1 is durable; pick it. ~20-40 LOC subshell wrap pattern in the test file.

**Complexity:** S-M (1 file edit, ~40 LOC wrapper pattern; no skill SKILL.md edits → no version bumps). **Action now:** /do pr — wrap each `test-create-worktree.sh` case in a hermetic subshell (per-case `GIT_CONFIG_GLOBAL` + `HOME` + `refs/heads/<prefix>` cleanup); verify all 26 cases still pass + suite stable across reorderings.

---

### #535 — /land-pr REBASE_STDERR_FILE key in result schema but no caller parses it

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `skills/land-pr/SKILL.md:170` declares `REBASE_STDERR_FILE` in the result-file schema and writes it on Step-6b failures (`SKILL.md:564` + step-9 line 829), but the canonical allow-list parser (`skills/land-pr/references/caller-loop-pattern.md:87-89`) and **all 5 caller copies** (`run-plan/modes/pr.md:402`, `fix-issues/modes/pr.md:158`, `do/modes/pr.md:277`, `commit/modes/pr.md:166`, `quickfix/SKILL.md:1127`) omit it from their case statements. Every Step-6b failure produces a `WARN: /land-pr result has unknown key REBASE_STDERR_FILE — ignoring` log + a `/tmp/land-pr-auto-rebase-stderr-*-*.log` sidecar leak.

**Fix outline.** Add `REBASE_STDERR_FILE` to the case-arm allow-list in 6 sites (canonical pattern + 5 caller copies). Add the sidecar path to `_CLEANUP_PATHS` so it's tidied up alongside the other land-pr sidecars. Mechanical: mirror the existing allow-list pattern. All 6 skill SKILL.md files get version bumps + mirrors.

**Complexity:** S (6-file allow-list addition + _CLEANUP_PATHS update; 6 SKILL.md version bumps via skill-versioning discipline). **Action now:** /do pr — add `REBASE_STDERR_FILE` to allow-list in all 6 sites + extend `_CLEANUP_PATHS`; bump each affected skill's `metadata.version` and mirror.

---

### #528 — hooks/_lib/git-tokenwalk.sh `is_git_subcommand` missing path-strip → /usr/bin/git invocations bypass all git-side gates

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `hooks/_lib/git-tokenwalk.sh:60` `is_git_subcommand` checks first token against literal `"git"` after quote-stripping; does NOT path-strip. So `/usr/bin/git push origin main` → token `/usr/bin/git` → no match → hook returns "not a git command" → ALL git-side gates silently allow (BLOCK_MAIN_PUSH, stash gate, commit --no-verify gate, etc.). The sister helper `is_gh_pr_subcommand:444-450` correctly path-strips via `case "$g" in */*) g="${g##*/}" ;; esac`. The git variant is missing the same one-line guard.

**Fix outline.** Add the one-line path-strip to `is_git_subcommand` between the quote-strip at line 77 and equality check at line 79. Mirror the addition into every hook that inlines this helper via the drift gate (helper is inlined, not sourced from .claude/hooks/_lib/). Add regression test cases to `tests/test-hooks.sh`: `/usr/bin/git push origin main` (expect deny on main), `./git commit --no-verify` (expect deny), `/usr/local/bin/git checkout -- file` (expect deny). Update `tests/test-hook-helper-drift.sh` if it asserts the helper surface. Same family as #515.

**Complexity:** S-M (1 line fix in helper source + cascading drift updates across inlined consumers + 3-4 test cases). **Action now:** /do pr — add path-strip to `is_git_subcommand` in `hooks/_lib/git-tokenwalk.sh`; propagate inlined copies across all 3 hook consumers (`block-unsafe-generic.sh`, `block-unsafe-project.sh.template`, `block-stale-skill-version.sh`); mirror to `.claude/hooks/`; add path-prefixed test cases to `tests/test-hooks.sh`.


---

### #547 — /run-plan PR mode: requires.land-pr blocks intermediate feature-branch commits

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `block-unsafe-project.sh:805-810` enforces ALL `requires.*` markers on every `git commit` in a pipeline. But `requires.land-pr` (written by `/run-plan` PR mode at SKILL.md:926-931) is fulfilled AFTER the very feature-branch commits the gate blocks. Verifier subagent's per-phase commit on `feat/<plan-slug>` is blocked. Workaround pattern (delete marker → commit → rewrite) was used in PR #544 but acknowledged as patch-not-fix. Two markers (`requires.verify-changes` vs `requires.land-pr`) have different fulfillment timing but identical enforcement.

**Fix outline.** Option 1 (recommended in body): gate `requires.*` enforcement to fire only when current branch is main/master. Reuse existing `is_on_main()` helper. Push-to-main (the actual landing event) remains gated. Feature-branch commits (`feat/*`, `fix/*`, `cp-*`) bypass the requires check. ~3 line change in `block-unsafe-project.sh.template` (+ mirror to `.claude/`); add regression test case for "commit on feature branch in pipeline with unfulfilled requires" → should ALLOW.

**Complexity:** S (3 LOC change + 1-2 test cases; .template + .claude mirror; no SKILL.md edits → no version bumps unless skill SKILL.md prose changes too). **Action now:** /do pr — wrap the `for req in $PIPELINE_SUBDIR/requires.*` loop at `block-unsafe-project.sh.template:805-810` with `if ... && is_on_main; then`; mirror to `.claude/hooks/block-unsafe-project.sh`; add a test case to `tests/test-hooks.sh` (or `tests/test-hook-requires-fulfilled.sh` if it exists) asserting commit-on-feature-branch in a pipeline with unfulfilled `requires.*` ALLOWS.

---

### #546 — /work-on-plans schedule_under_1h minute-form check missing N<60 comparison

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `skills/work-on-plans/SKILL.md:1068-1082` defines `schedule_under_1h`. The cron-form regex correctly compares `n` to 60; the **minute-form regex** matches any `<N>m` and returns 0 (true = sub-hour) without comparing N to 60. So `60m`, `120m`, `1440m` are misclassified as sub-hour and get the "must be ≥1h" rejection.

**Fix outline.** One-line fix: replace the minute-form's bare `&& return 0` with a numeric guard mirroring the cron-form pattern at the very next line. Source SKILL.md edit → version bump per skill-versioning discipline → mirror.

**Complexity:** S (1 line of new conditional + `metadata.version` bump + mirror). **Action now:** /do pr — change `skills/work-on-plans/SKILL.md:1073` minute-form consequent to compare `n` against 60 (mirrors the cron-form pattern at line 1077); bump `work-on-plans` SKILL.md version + mirror.

---

### #515 — block-unsafe-generic.sh: git push origin HEAD bypasses BLOCK_MAIN_PUSH from main

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `hooks/block-unsafe-generic.sh:597-635` has been hardened multiple times for `main` spelling variants but missed `HEAD`. Parser normalizes `HEAD` through colon-strip / `+`-strip / `refs/heads/`-strip but never resolves `HEAD` → current local branch. Result: from `main` branch, `git push origin HEAD` resolves server-side to `origin/main` but the parser sees literal `HEAD ≠ main` → ALLOWED. Same family as #470/#392/#457/#399/#426/#427 enumeration closures; this gap completes the family. The project hook (`block-unsafe-project.sh.template`) has the same gap.

**Fix outline.** After existing normalizations + before equality check, resolve `PUSH_TARGET = "HEAD"` via `git branch --show-current` to the current local branch name. Apply same in `hooks/block-unsafe-project.sh.template`. Mirror both to `.claude/hooks/`. Add tests at `tests/test-hooks.sh`: `git push origin HEAD` from main → DENY; from `feat/*` → ALLOW. Same enumeration discipline as #528 (which just shipped path-strip for a sister bug).

**Complexity:** S-M (~3 line resolver in 2 files + 2 mirrors + 2 test cases). **Action now:** /do pr — add `HEAD` resolution after existing normalizations in `block-unsafe-generic.sh` push gate + `block-unsafe-project.sh.template` rule (a); mirror both to `.claude/hooks/`; add path-and-branch toggle test cases at `tests/test-hooks.sh:408+`.


---

### #511 — Verifier tally check missing — counts intermediate PASS lines, misses regressions

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `.claude/agents/verifier.md` test-validation prose counts inline PASS lines but does NOT validate the final `Overall: N/M passed` tally OR compare against a captured baseline. Observed 2026-05-18 with 2 regressions slipped through (Tier-1 drift + commit-cohabitation) — verifier reported 3313/3313 but the real tally was 3311/3313. Same defect mirrors into skill SKILL.md prompts that drive orchestrator-side test runs (e.g., `/run-plan` Phase 4 verification).

**Fix outline.** Add to `.claude/agents/verifier.md` test-validation section (and mirror into skill prompts that perform inline test validation): require the verifier to (1) assert the test output contains `Overall: N/M passed`; (2) assert N == M; (3) if a pre-impl baseline pass-count was captured, require N >= baseline_N; (4) if the summary line is absent → FAIL (truncation / hang signal). No test needed — this is agent-prompt prose; effectiveness is validated by the next sprint that exercises it.

**Complexity:** S (1 file edit on `.claude/agents/verifier.md`; possibly 1-2 skill SKILL.md prompts to mirror; no version bumps for `.claude/agents/` files). **Action now:** /do pr — add Overall-line tally check to `.claude/agents/verifier.md` test-validation prose; grep skill SKILL.md prompts for "test-validation" or "run tests" patterns and mirror the discipline where it's needed.

---

### #510 — /fix-issues research-blurb + impl-prompt missing tier1-hash-registration step

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `skills/update-zskills/references/tier1-shipped-hashes.txt` is the Tier-1 file-hash registry. When a fix-PR modifies a Tier-1 file (e.g., `briefing.py`, `sanitize-pipeline-id.sh`), the SAME PR must register the new blob's SHA-1 in the registry or CI fails. This requirement is NOT encoded in `skills/fix-issues/` SKILL.md — neither research-blurb template nor impl-prompt template. Four observed CI failures (sprints from 2026-05-20). Orchestrators began per-invocation hand-injection of the step — exactly the "skill-framework repo — surface bugs, don't patch" anti-pattern CLAUDE.md forbids.

**Fix outline.** Add prose to `skills/fix-issues/SKILL.md` impl-prompt template: "If your fix modifies a Tier-1 file (per `skills/update-zskills/references/tier1-shipped-hashes.txt`), the SAME commit must update that file's blob hash entry in the registry." Optionally add a detection helper that pre-computes the Tier-1 intersection for the orchestrator (issue body sketches the bash). Bump `/fix-issues` SKILL.md `metadata.version` per the discipline; mirror.

**Complexity:** S (1-2 prose block additions to `/fix-issues` SKILL.md + version bump + mirror; possibly a test asserting the prose appears). **Action now:** /do pr — add tier1-hash-registration prose to the impl-prompt construction section of `skills/fix-issues/SKILL.md`; bump version + mirror; consider a small conformance assertion that ensures the prose is present.


---

### #557 — /run-plan Phase 4 verifier dispatch prompt instructs `git diff main...<branch>` symmetric anti-pattern

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** PR #453 (closing #448) fixed `.claude/agents/verifier.md` to use merge-base form (`git diff $(git merge-base origin/main HEAD)..HEAD`) and forbid symmetric `main...<branch>` + bare `origin/main..HEAD --stat`. But the orchestrator-supplied Phase 4 dispatch prompt at `skills/run-plan/SKILL.md:1592-1593` STILL instructs the verifier to use `git diff main...<branch>` — three-dot symmetric AND bare `main` (no `origin/`). The orchestrator's prompt overrides the agent file's defense. Same documented two-failure incident (PR #447 landing window 2026-05-19/20) is one cron-fire away from re-firing.

**Fix outline.** Two-line edit at `skills/run-plan/SKILL.md:1592-1593` to replace the symmetric-diff instruction with the merge-base form + explicit "Do NOT use `main...<branch>` or bare `origin/main..HEAD --stat`" prohibition. Add conformance tripwire at `tests/test-skill-conformance.sh` asserting `main\.\.\.` does NOT appear in `skills/**/*.md` (one-sided defense today: existing tripwire asserts GOOD form IS in verifier.md). Bump `/run-plan` SKILL.md version + mirror.

**Complexity:** S (5-line prose edit + 1 conformance tripwire + version bump + mirror). **Action now:** /do pr — replace symmetric-diff instruction in `skills/run-plan/SKILL.md:1592-1593` with the merge-base form (mirror verifier.md's prose); add conformance tripwire forbidding `main\.\.\.` in `skills/**/*.md`; bump SKILL.md version + mirror.

---

### #556 — PR #553 closure-incomplete: property-test matrix not extended to enumerate `target=HEAD`

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** PR #553 (#515 HEAD fix) added runtime resolution + 4 hand-written `toggle_test` cases. But the property-test matrix at `tests/test-hooks.sh:2300` (generic) + `:2382` (project) still iterates `for target in main master feat/test` — `HEAD` is NOT in the target set. The 4 hand-written cases cover ~4 of the ~280 combinatorial variants. Wrappers + force-prefixes + refspec-RHS forms × HEAD aren't locked. Same pattern as #470 (follow-up to #457's incomplete closure) — the patch-react-ship cycle of the #513/#522 matrix-buildout exists specifically to terminate.

**Fix outline.** Extend the `for target in` loops at `tests/test-hooks.sh:2300` (generic) and `:2382` (project) to include `HEAD`. Add a branch-context axis (`for branch in main feat/test`) so HEAD target asserts DENY from main checkouts + ALLOW from feature-branch checkouts. Combinatorial expansion roughly doubles the matrix to ~560 cases — cheap to run. No skill SKILL.md edits → no version bumps.

**Complexity:** S-M (matrix axis extension; ~10-20 LOC additions; pure test). **Action now:** /do pr — add `HEAD` to target loop at `tests/test-hooks.sh:2300` + `:2382`; add `branch` axis so HEAD-from-main DENIES and HEAD-from-feat ALLOWS; full combinatorial expansion with existing wrapper / force-prefix / ref-prefix / refspec-form / quote-style axes.


---

### #561 + #556 (bundled) — project-hook HEAD wrapper-quote bypass + property-matrix extension

**Labels:** bug | **Verdict:** NOT FIXED — bundled fix

**Problem.** Two coupled defects from PR #553's closure-incompleteness:
- **#561**: `block-unsafe-project.sh.template:1057-1071` HEAD-rewrite block matches case patterns against PUSH_ARGS words but does NOT strip trailing single/double quotes that wrapper-unwrapped forms leave behind. After `${PUSH_CMD##*git push}`, `bash -c 'git push origin HEAD'` yields word `HEAD'` (with trailing apostrophe) → no rewrite → rule (a) sees no `main` → ALLOW. Universal main-protection bypass for wrapper-quoted git push.
- **#556**: `tests/test-hooks.sh:2300` + `:2382` property-test matrix never enumerated `target=HEAD`. The matrix exists precisely to terminate the patch-react-ship cycle of the BLOCK_MAIN_PUSH family (#73 / #87 / #195 / #197 / #306 / #413 / #417 / #434 / #435 / #465 / #486 / #470 / #515). Adding `HEAD` to the target axis with a branch-context axis surfaces 120 of 280 wrapper-quoted variants as the #561 bypass.

**Fix outline.** Bundled PR closes both:
1. **Project-hook quote-strip** (`block-unsafe-project.sh.template:1057-1071`): add per-word `case ... \'*\' \"*\"` quote-strip BEFORE the HEAD case-match (mirrors the generic hook's pattern at `block-unsafe-generic.sh:625-626`). Apply to `.claude/hooks/block-unsafe-project.sh` mirror.
2. **Property-test matrix extension** (`tests/test-hooks.sh:2300` + `:2382`): apply the prepared diff at `/tmp/issue-556-matrix-extension.patch` (264 lines; adds `HEAD` to target axis + `branch ∈ {main, feat/test}` axis; expected ~1400 total cases). Verify all 280 project-hook HEAD variants now PASS (vs the 120 FAIL with the bypass).
3. **No skill SKILL.md edits** → no version bumps. Hooks + tests only.

**Complexity:** S-M (~5 LOC quote-strip + apply 264-line matrix patch + verify). **Action now:** /do pr — apply matrix patch from `/tmp/issue-556-matrix-extension.patch`; add quote-strip to project-hook HEAD-rewrite (mirror generic's pattern); mirror to .claude/hooks/; verify all 280 project-hook HEAD-axis cases PASS.


---

### #564 — Property-matrix conformance net itself unprotected against shrinkage

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** Property matrix at `tests/test-hooks.sh:2300`+`:2382` (added by #556/PR #565 — 1400 HEAD-axis cases) is not gated against silent shrinkage. If a future agent reverts the `for branch in main feat/test` or removes `HEAD` from `for target in ...`, all cases vanish; suite still reports 0 failures. The conformance defense relies on the matrix to catch BLOCK_MAIN_PUSH bypass family variants — a load-bearing test net must itself be protected.

**Fix outline.** Add static structural conformance assertions to `tests/test-skill-conformance.sh` (or a new `tests/test-hooks-matrix-invariants.sh`) gating against shrinkage: (1) assert `for branch in main feat/test` appears ≥2× (one per matrix section); (2) assert `for target in ... HEAD ...` (or `target=HEAD` injection) appears ≥2×. Static greps; cheap, fail-closed. No skill SKILL.md edits → no version bumps.

**Complexity:** S (~10 LOC test assertions + 1 line in run-all.sh if new file). **Action now:** /do pr — add 2-3 structural assertions to `tests/test-skill-conformance.sh` (or a new tests/test-hooks-matrix-invariants.sh) asserting the matrix's axis invariants are present.


---

### #567 — transparent-prefix bypass: `nohup`/`timeout`/`command`/`exec`/`nice`/`time` before git

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `is_git_subcommand` (`hooks/_lib/git-tokenwalk.sh:60-110`) and `is_destruct_command` don't skip transparent command-prefix wrappers. Sister `is_gh_pr_subcommand:400-447` (PR #255 closing #279) handles `command|exec|nohup|nice|time|timeout`. `timeout 30 git push origin main` from main → NOMATCH (bypass). Universal bypass on every git-side gate (BLOCK_MAIN_PUSH, stash gate, commit --no-verify, etc.) AND every destruct gate (rm/kill family). Same structural-asymmetry shape as #528 (closed by PR #550 — path-strip parity) — one prefix family deeper.

**Fix outline.** Extract the prefix-skip block from `is_gh_pr_subcommand:420-447` into a shared helper `skip_transparent_prefixes` (or inline-mirror the block into `is_git_subcommand` + `is_destruct_command`). Propagate to 3 inlined consumers (`block-unsafe-generic.sh`, `block-unsafe-project.sh.template`, `block-stale-skill-version.sh`). Mirror to `.claude/hooks/`. Add property-test axis enumerating `{nohup, timeout 30, timeout --foreground 30, command -p, exec, nice, time}` × `{git push, git commit --no-verify, rm -rf}` × `{branch=main, branch=feat}` so the closure is locked.

**Complexity:** S-M (helper extraction OR inline mirror at 2 sites + 3 inlined consumers + mirrors + property-axis extension). **Action now:** /do pr — mirror `is_gh_pr_subcommand`'s `skip_transparent_prefixes` into `is_git_subcommand` + `is_destruct_command` (or extract shared helper); propagate to 3 inlined consumers + .claude mirrors; extend property matrix to enumerate transparent-prefix × command axis.


---

### #572 — is_destruct_command missing path-strip — `/usr/bin/kill -9`, `nohup /usr/bin/killall` bypass

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** Sister bug to #528 (closed by PR #550). `is_destruct_command` in `hooks/_lib/git-tokenwalk.sh` got the transparent-prefix skip from #567 but NEVER received the path-strip from #528. Result: `/usr/bin/kill -9 1234`, `nohup /usr/bin/killall node`, `/usr/local/bin/pkill foo` bypass the destruct gate. Same enumeration-closure family as #528/#515/#567.

**Fix outline.** Add `case "$first" in */*) first="${first##*/}" ;; esac` to `is_destruct_command` (mirror of the existing pattern in `is_git_subcommand`). Apply to source + 3 inlined consumers + .claude mirrors. Extend property-test matrix to include `/usr/bin/kill`, `nohup /usr/bin/killall`, `/usr/local/bin/pkill` × destruct verbs.

**Complexity:** S (1-line addition × 4 files + mirrors + ~6 test cases). **Action now:** /do pr — mirror #528's path-strip pattern into `is_destruct_command` source + 3 inlined consumers + .claude mirrors; add property-test cases.

---

### #573 — #516 regression tests not wired into tests/run-all.sh

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** PR #532 (#516 silent commit-loss fix) added `tests/test-cleanup-merged-ahead-gate.sh` + `tests/test-briefing-worktrees-merged-diverged.sh`. Both files exist; neither is invoked by `tests/run-all.sh`. The data-loss-class fix has no canonical-runner regression net — a future revert would not trip CI.

**Fix outline.** Add 2 `run_suite` lines to `tests/run-all.sh` registering both test files. Trivial wire-up; no other surface touched.

**Complexity:** S (2-line wire-up). **Action now:** /do pr — add 2 `run_suite` entries to `tests/run-all.sh` for the #516 regression tests in the appropriate section.

---

### #580 — /session-report points at flat tracking-marker path; canonical is nested

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `skills/session-report/SKILL.md:63` directs the agent to verify "Plan executed" claims via `.zskills/tracking/fulfilled.run-plan.<slug>` (flat layout). Canonical scheme per `docs/tracking/TRACKING_NAMING.md:44` and `/run-plan` write sites is **nested**: `.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*`. The ground-truth-auditor skill itself has stale ground-truth paths — agent follows the table literally, finds zero matches, concludes "no run-plan evidence" — ironic failure mode where the auditor misses ground truth because its own command is wrong.

**Fix outline.** Replace flat path with nested `$PIPELINE_ID/fulfilled.run-plan.*` (or equivalent — read the file for context). Bump session-report SKILL.md `metadata.version` per skill-versioning discipline. Mirror.

**Complexity:** S (1-line prose fix + version bump + mirror). **Action now:** /do pr — replace flat tracking path at `skills/session-report/SKILL.md:63` with nested `$PIPELINE_ID/fulfilled.run-plan.*` form; bump version + mirror.


---

### #587 — Test-isolation flake mystery — actually 1 intermittent assertion + diagnostic noise

**Labels:** bug | **Verdict:** NOT FIXED — root cause diagnosed

**Problem.** Diagnosis (orchestrator + bisection): the "3 failures non-deterministic under `bash tests/run-all.sh`" is NOT a multi-test isolation flake. Root cause is at `tests/test-hooks.sh:4500-4558` — the "Fixture-extension coverage" section invokes `bash tests/test-skill-conformance.sh` against a synthetic fixture dir at `/tmp/zskills-fixture-extension-test/`. The synthetic fixture has only `skills/synthetic/SKILL.md` — all OTHER conformance assertions (against skills/run-plan, skills/verify-changes, etc.) EXPECTEDLY FAIL because the synthetic dir lacks real skills. The single OUTER test assertion is `grep -q '__TEST_LITERAL__' "$EXT_DENY_OUT"`. When that ONE assertion fails, `head -50 "$EXT_DENY_OUT" >&2` dumps 50 lines of expectedly-failing conformance output as diagnostic — producing the false impression of 15-20 separate `[run-plan] FAIL` lines.

**Fix outline (2 parts):**

- **Part A (this PR)**: replace `head -50 "$EXT_DENY_OUT" >&2` at `tests/test-hooks.sh:4555` with a tighter diagnostic that prints ONLY the deny-list section (or just confirms `__TEST_LITERAL__` absence with a sentinel-only diagnostic). Eliminates ~17 phantom FAIL lines from sprint reports.
- **Part B (follow-up issue)**: investigate why the outer assertion intermittently fails. Likely the synthetic fixture missing some path the conformance test's deny-list depends on. Out of scope for this PR.

**Complexity:** S (single-file edit, ~5-10 LOC). **Action now:** /do pr — replace the `head -50 ... >&2` diagnostic with a tighter grep (`grep -A 2 -B 2 'deny-list\|forbidden-literals\|__TEST_LITERAL__' "$EXT_DENY_OUT" >&2` or `tail -10 ...`); file Part B as a follow-up issue.

---

### #586 — Destruct gate has no _in_wrappers variant — bash -c '/usr/bin/kill -9' bypasses

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** Sister gap to #572 (closed by PR #588). `is_destruct_command_in_chain` exists; `is_destruct_command_in_wrappers` does NOT. Wrapper-quoted forms like `bash -c '/usr/bin/kill -9 1234'`, `eval 'killall node'` bypass the destruct gate even after #572 added path-strip. Universal silent bypass.

**Fix outline.** Add `is_destruct_command_in_wrappers` helper to `hooks/_lib/git-tokenwalk.sh` modeled on `is_git_subcommand_in_wrappers`. Iterates wrapper bodies (`bash -c`, `sh -c`, `eval`, etc.) and applies `is_destruct_command_in_chain` to the extracted command string. Update the destruct-gate consumer (`hooks/block-unsafe-generic.sh`) to call the new wrappers helper first, falling back to `_in_chain`. Mirror to `.claude/hooks/`. Extend property matrix in `tests/test-hooks.sh` enumerating wrapper × destruct-verb × path-prefix combinations.

**Complexity:** S-M (1 new helper + 1 consumer update + mirrors + ~8 property cases). **Action now:** /do pr — add `is_destruct_command_in_wrappers` to `hooks/_lib/git-tokenwalk.sh` mirroring the gh-variant pattern; wire into `block-unsafe-generic.sh`; mirror; extend test-hooks.sh property matrix.

---

### #578 — /run-plan textual-staleness should dispatch /refine-plan, not /draft-plan

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** `skills/run-plan/SKILL.md:800-805` Phase 1 step 6a textual-staleness path dispatches `/draft-plan` to refresh stale plans; the symmetric arithmetic-staleness path at line 846 dispatches `/refine-plan`. Both should use `/refine-plan` (correct skill — refines existing plans rather than re-drafting).

**Fix outline.** 2-line prose edit at `skills/run-plan/SKILL.md:800-805`: replace `/draft-plan` with `/refine-plan` in both prose mentions (interactive prompt + auto dispatch instruction). Bump `/run-plan` SKILL.md `metadata.version` per skill-versioning discipline. Mirror.

**Complexity:** S (2-line prose fix + version bump + mirror). **Action now:** /do pr — replace `/draft-plan` with `/refine-plan` at `skills/run-plan/SKILL.md:800-805` to match the symmetric arithmetic-staleness path; bump version + mirror.


---

### #596 + #592 + #582 + #579 (bundled) — skill bash fences read unassigned variables

**Labels:** bug | **Verdict:** NOT FIXED — bundled family fix

**Problem.** Four skills have bash fences that READ variables without first assigning them, causing fail-closed or silent-skip on direct invocation:
- **#596**: `/refine-plan` worktree preamble reads `${TRACKING_ID}` (lines 76, 79) + `$PLAN_FILE` — never assigned
- **#592**: `/draft-tests` worktree preamble reads `${TRACKING_ID}` (lines 79, 82) before assignment at line 160; `$PLAN_FILE` never assigned
- **#582**: `/research-and-go` Step 2 reads `$GOAL` for landing-mode detection — never assigned
- **#579**: `/research-and-plan` standalone Tracking fence reads `$META_PLAN_PATH` — never assigned; `sanitize-pipeline-id` fail-closes the fence

Same structural shape across all four. Each skill works fine when DISPATCHED by a parent (which sets the var beforehand) but FAILS on direct standalone invocation.

**Fix outline.** For each skill: locate the worktree preamble / Step 2 / Tracking fence; add an explicit ARGUMENTS-parsing block at the top that assigns the missing variable(s) from `$ARGUMENTS` or with a sensible default. Bump each skill's `metadata.version` per discipline + mirror. ~3-5 LOC per skill.

**Complexity:** S-M (4 SKILL.md edits + 4 version bumps + 4 mirrors). **Action now:** /do pr — assign the missing variables at the head of each affected fence/section; bump versions + mirror.

---

### #575 + #576 (bundled) — conformance tripwire follow-ups (verifier tally + REBASE_STDERR_FILE allow-list)

**Labels:** bug | **Verdict:** NOT FIXED — bundled conformance extension

**Problem.** Two closure-incomplete follow-ups; both extend `tests/test-skill-conformance.sh`:
- **#575**: #511's tally-check conformance tripwire pins `.claude/agents/verifier.md` only; the `skills/run-plan/SKILL.md` mirror (with the same tally prose) is unguarded. Reverting the mirror would regress #511 silently.
- **#576**: #535's allow-list conformance assertion still pins only the legacy 3-key pattern (`STATUS|PR_URL|PR_NUMBER`). `REBASE_STDERR_FILE` (and other sidecar keys) added by #535 are not asserted. Dropping `REBASE_STDERR_FILE` from any of the 6 caller allow-lists would regress silently.

Both fixes extend `tests/test-skill-conformance.sh` with grep-counting tripwires. Same pattern, single file, bundled into one PR to avoid conflicts.

**Fix outline.** For #575: add `grep -c 'Overall: N/M passed' skills/run-plan/SKILL.md >= 1` (or equivalent grep against the canonical tally prose) to test-skill-conformance.sh. For #576: extend the existing allow-list assertion at lines 1248 + 1292-1293 to include `REBASE_STDERR_FILE` (and the full canonical key set: `CONFLICT_FILES_LIST`, `CALL_ERROR_FILE`, etc.). No skill SKILL.md edits.

**Complexity:** S (2-3 grep assertions added to tests/test-skill-conformance.sh, no version bumps). **Action now:** /do pr — extend test-skill-conformance.sh with #575's tally tripwire on run-plan/SKILL.md + #576's full-key-set allow-list pin.

---

### #574 — claim primitive test coverage gap

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** PR #544 (c3509dc) shipped the Phase 1 claim primitive with 13 unit tests on `claim-issue.sh` itself. Two adjacent surfaces have no test coverage: (1) `sweep_stale_claims` helper wrapper in `claim-fence-helpers.sh`; (2) `zskills-resolve-config.sh` parsing of the `claim_ttl_seconds` config field. Existing tests only `export ZSKILLS_CLAIM_TTL_SECONDS=7200` directly, bypassing the resolver.

**Fix outline.** Add test cases to existing `tests/test-fix-issues-claim-script.sh` (or extract into a focused new file) for: (1) `sweep_stale_claims` wrapper — invoke via the SKILL fence shape, assert it sweeps + reports correctly; (2) `claim_ttl_seconds` resolver — set the config field, invoke `zskills-resolve-config.sh`, assert `ZSKILLS_CLAIM_TTL_SECONDS` is set from config. ~10-20 LOC of new test cases.

**Complexity:** S (test additions in existing file; no source edits). **Action now:** /do pr — add `sweep_stale_claims` test cases + `claim_ttl_seconds` config-resolver test cases to `tests/test-fix-issues-claim-script.sh`.

---

### #602 — /fix-report Step 6 case statement masks failure-class statuses (failed, direct-push-failed, direct-verify-failed) as generic 'PARTIAL' — contradicts the skill's own prose

**Labels:** (none) | **Verdict:** NOT FIXED

**Problem.** `skills/fix-report/SKILL.md` Step 6 (lines 352-371) classifies worktrees by `.landed` `status:` value with 5 explicit case arms (`full|landed`, `pr-ready`, `pr-ci-failing`, `pr-failed`, `conflict`); the `*)` wildcard collapses everything else — including failure-class statuses `failed`, `direct-push-failed`, `direct-verify-failed`, `pr-state-unknown`, and `partial` — to generic "PARTIAL — has unlanded or unresolved work." Same SKILL.md prose (lines 272-276) explicitly says these failure-class markers must be "surface[d] in the report as failed sprints" — case statement contradicts the prose; case statement wins at runtime. Reader-side of the same vocabulary expansion #518 / #530 handled writer-side; `tests/test-landed-schema.sh:158-175` checks `status:` substring but cannot detect case-arm drift.

**Fix outline.** Extend the case statement with 3 new arms: `failed|direct-push-failed|direct-verify-failed)` → FAILED label (failure-class, see reason field); `pr-state-unknown)` → NEEDS ATTENTION (PR state unverified); `partial)` → explicit PARTIAL label (vs. silent collapse). Replace generic `*)` arm with `UNKNOWN: unrecognized status` so future status drift fails loudly. Tighten `tests/test-landed-schema.sh` to assert each documented status (`full`, `landed`, `pr-ready`, `pr-ci-failing`, `pr-failed`, `conflict`, `failed`, `direct-push-failed`, `direct-verify-failed`, `pr-state-unknown`, `partial`) appears as a case-arm pattern in `/fix-report` SKILL.md — mirror-of-existing-pattern from #586 / #587 closure-tightening tests. Bump `/fix-report` `metadata.version` per skill-versioning discipline; mirror to `.claude/skills/`.

**Complexity:** S (one case-statement extension + one test extension + version bump + mirror). **Action now:** /do pr — add 3 failure-class case arms (FAILED + pr-state-unknown + partial) to `skills/fix-report/SKILL.md:352-371`; replace `*)` arm with loud-fail UNKNOWN; extend `tests/test-landed-schema.sh` with per-status case-arm grep loop; bump version + mirror.

---

### #601 — /fix-issues PR-mode body uses `${CHANGE_SUMMARY}` (modes/pr.md:110) but variable is never assigned — every PR ships with empty "## Changes" section

**Labels:** (none) | **Verdict:** NOT FIXED — confirmed defect, 5th sibling in variable-read-never-assigned family

**Problem.** `skills/fix-issues/modes/pr.md` composes a per-PR body via an unquoted heredoc (lines 102-115) that expands `${CHANGE_SUMMARY}`, but no assignment exists anywhere in the executable path (`grep -rnE '^[[:space:]]*CHANGE_SUMMARY=' skills/fix-issues/` returns empty). Result: every /fix-issues PR-mode PR — the dominant PR producer in this repo via the hourly cron — ships with a blank `## Changes` section, stripping context from human reviewers and from downstream consumers (sprint reports, /fix-report, briefings) that scan PR bodies. Fifth confirmed sibling of the variable-read-before-assignment family alongside #579 (META_PLAN_PATH), #582 ($GOAL), #592 (TRACKING_ID + PLAN_FILE in /draft-tests), and #596 (TRACKING_ID + PLAN_FILE in /refine-plan).

**Fix outline.** Assign `CHANGE_SUMMARY` immediately before the heredoc at line 102 by deriving it from `git log origin/main..HEAD --format='- %s'` inside `$WORKTREE_PATH`, with a fallback string when no commits exist yet (e.g. `_(no commits yet — body will be updated on first push)_`). ~5-line addition to `skills/fix-issues/modes/pr.md`. Add a conformance test pin asserting every `${VAR}` referenced inside heredoc fences in `modes/pr.md` has a same-file assignment (mirrors the #592/#596 pattern; ideally a framework-level invariant closing the whole 5-sibling family at once). Bump `metadata.version` per skill-versioning rule.

**Complexity:** S (single-file ~5-line bash assignment + conformance test pin + metadata version bump). **Action now:** /do pr — add `CHANGE_SUMMARY=$(git log origin/main..HEAD --format='- %s')` assignment before the heredoc in `skills/fix-issues/modes/pr.md`, add conformance assertion against unset-heredoc-vars in `modes/pr.md`, and bump the skill's `metadata.version`.


### #606 — Variable-read-before-assignment family: close remaining 4 siblings + add structural conformance pin in one PR

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** Pass-18 closure-verification on PR #603 (which closed #579/#582/#592/#596) surfaced 4 more uncovered siblings of the variable-read-before-assignment defect family: #601 (now closed by PR #614), `skills/draft-plan/SKILL.md:65` (`${TRACKING_ID}` zero assignments), `skills/fix-issues/SKILL.md:321-323` (`${TRACKING_ID}` zero assignments — trickier because /fix-issues doesn't take a plan file), and `skills/run-plan/SKILL.md:271` (`$PLAN_FILE` in status-mode fence; first assignment is line 1323, status-mode exits before Phase 1 preflight). PR #603 was hand-crafted to 4 specific skills with no conformance pin to prevent the next sibling from accreting.

**Fix outline.** One PR adds the structural conformance pin to `tests/test-skill-invariants.sh` (~30-50 lines bash extracting every `${VAR}` read inside fenced bash blocks per skill and asserting either same-file assignment, env-var allow-list, or inspectable allow-comment marker), plus mirrors the #603 `$ARGUMENTS`-resolution pattern to the 3 remaining siblings (draft-plan TRACKING_ID/OUTPUT_FILE/ROUND, fix-issues SKILL.md TRACKING_ID with synthesized `sprint-$(TZ=… date)` form, run-plan status-mode PLAN_FILE), plus 3 version bumps + 3 mirrors. Closes #606.

**Complexity:** M (3 mechanical mirrors of #603's `$ARGUMENTS`-resolution pattern in draft-plan + run-plan status-mode; 1 sprint-mode-mirror synthesis in fix-issues sync mode using the already-established `sprint-$(date)` shape; 1 conformance pin ~30-50 lines bash mirroring existing test-skill-invariants.sh patterns; 3 version bumps + 3 mirrors). **Action now:** /do pr — corrected from earlier "/draft-plan" framing: the body's "consolidated work item" hint was misleading. Independent sizing of each cited sibling shows they're all mechanical (3 are direct mirrors of #603's pattern; the 4th uses fix-issues' already-canonical sprint-timestamp form). Multi-discipline (4 skills × source + mirror + version bump) but not novel-design. /do pr's pre-execution plan-review will catch any scope drift across the 4 surfaces.

### #604 — /run-plan PR mode: per-phase step.*.{implement,verify,report} markers never propagate to main

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** In `/run-plan` PR mode, `step.run-plan.<id>.{implement,verify,report}` markers are written to the worktree (gitignored, ephemeral) and never copied to main. Only `step.run-plan.<id>.land` lands in main (Phase 6 uses `MAIN_ROOT="$CLAUDE_PROJECT_DIR"`). When the PR merges (squash) and the worktree is removed, the worktree's `.zskills/tracking/` subtree vanishes — main is left with `.implement` + `.land` and no `.verify` or `.report` companions. Observed during `plans/fix-issues-claims.md` chunked-finish-auto run (PR #600): the post-`/clear` Phase 2 commit hit `hooks/block-unsafe-project.sh enforce_step_verify_marker` ("BLOCKED: ... verified but no report written") because main's tracking subdir had `.verify` (7h old) but no `.report` companion.

**Fix outline.** Option A from the issue body: add a copy-to-main step in `/land-pr` Step 7b adjacency (after FF local main succeeds for a squash-merged PR with `MERGE_REQUESTED=true` and `PR_STATE=MERGED`): `cp -af "$WT_TRACK/." "$MAIN_TRACK/"` for the entire `$PIPELINE_ID` subdir. Last-run-wins on collision. Includes `requires.*` and `fulfilled.*` markers so main has a complete view post-merge. Edge cases (worktree removed before copy = no-op; pipeline subdir already exists = clobber) handled. Plus an integration test simulating the chunked-finish-auto Phase N→N+1 transition WITHOUT the manual catch-up the orchestrator did for #600.

**Complexity:** S (one block in `skills/land-pr/SKILL.md` Step 7b adjacency + one integration test + version bump + mirror). **Action now:** /do pr — add Option A copy-to-main step in `/land-pr` Step 7b adjacency after the FF-merge, plus a test simulating the Phase N→N+1 transition.

### #577 — /research-and-plan Step 2 self-contradicts on /draft-plan dispatch mechanism (Skill-tool MUST clause vs parallel-3-agent prose)

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `skills/research-and-plan/SKILL.md` Step 2 prescribes two incompatible dispatch shapes for `/draft-plan`. Lines ~90-128 state a Skill-tool MUST clause ("The Skill tool is the recursion mechanism … You — still at top-level … execute /draft-plan's research, review, and refine workflow as if its instructions were your own") which is intrinsically serial (only one Skill-tool body active at a time). Lines ~167-172 prescribe parallel-3 concurrent-agents semantics ("Dispatch at most 3 /draft-plan agents concurrently. Wait for each batch to complete before the next…") which are realizable only via the Agent tool, contradicting the MUST. The past-failure quote ("11 parallel agents caused load 67") is direct evidence agents were Agent-dispatching /draft-plan here — exactly the path the MUST forbids.

**Fix outline.** Pick the Skill-tool shape (already justified by load-67 incident + Anthropic's sub-sub-agent design) and rewrite the parallelism prose as serial batches: "Invoke `/draft-plan` once per sub-problem via the Skill tool. Each invocation runs the full multi-round review loop in your context before returning; this is intrinsically serial. Report progress between sub-plans. Do not Agent-dispatch (subagents lack the Agent tool, breaking /draft-plan's internal reviewer + devil's-advocate dispatch)." Remove the "at most 3 concurrent" clause and the load-67 past-failure quote (now structurally impossible). Add a conformance pin asserting `research-and-plan/SKILL.md` does not contain both "Skill tool" and "concurrently" within the Step 2 region (or pin the canonical serial-batches prose with literal-substring assertion).

**Complexity:** S (one prose rewrite in SKILL.md + one conformance pin + version bump + mirror). **Action now:** /do pr — rewrite Step 2 parallelism prose as serial-batches form; remove the contradictory "at most 3 concurrent" clause; add conformance pin.

### #594 — Part B follow-up to #587: investigate intermittent 'deny-list test missed appended literal' assertion fail in test-hooks.sh fixture-extension section

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** Part A (PR #587) eliminated diagnostic noise + fixed run_suite() parser miscount. The underlying intermittent assertion (`fixture-extension: deny-list test missed appended literal`) still fails occasionally. Likely cross-suite env-state leak (`REPO_ROOT`, `CLAUDE_PROJECT_DIR`, `GIT_*`); 100% pass in isolation (`bash tests/test-hooks.sh`). Body suggests several investigation paths (bisect, env-var examination, per-suite hermeticity, surgical teardown) but no root cause is pinned.

**Fix outline.** Investigation-first. Bisect which prior suite in `tests/run-all.sh` leaks state; examine env vars set by non-zero-exit suites; choose between (a) surgical teardown in the leaky test, or (b) broader `run_suite()` subshell+env-reset hermeticity. Picking a fix shape without root cause is guesswork.

**Complexity:** Unknown (depends on which suite leaks and which fix shape applies). **Action now:** /investigate #594 — root cause must be proven before fix shape can be chosen; "bug with unclear cause" triage bucket per /fix-issues skill rubric.

### #583 — /review-feedback prose lacks 'independently size severity' rule

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `skills/review-feedback/SKILL.md` Step 2 lacks a re-rate-severity instruction; the Step 5 body template hardcodes `**Severity:** high` echoing the reporter's self-rated field. Same rubber-stamping anti-pattern that QE_ISSUES.md memory anchors #404 and #444 are trying to terminate elsewhere. /review-feedback's outputs feed /fix-issues; pass-through severity propagates through every downstream sprint.

**Fix outline.** Add to Step 2: "Independently re-rate severity. The reporter's self-rated severity is a hint, not authoritative. Re-evaluate against impact (data loss > crash > broken feature > polish > nit) and frequency before filling the table." Rename Step 3's summary-table column header from "Severity" to "Re-rated Severity" to make independent rating visible. Conformance pin asserting `skills/review-feedback/SKILL.md` contains the literal "Independently re-rate severity".

**Complexity:** S (Step 2 prose addition + Step 3 column rename + conformance pin + version bump + mirror). **Action now:** /do pr — apply the Step 2 + Step 3 edits and add the conformance pin.

### #594 — Part B follow-up to #587: intermittent fixture-extension assertion fail

**Labels:** (none) | **Verdict:** RESEARCHED (persistent skip)

**Problem.** Part A (PR #587) fixed noise + parser miscount. Underlying intermittent assertion (`fixture-extension: deny-list test missed appended literal`) still fails occasionally. Likely cross-suite env-state leak; 100% pass in isolation. Multiple plausible fix shapes, no root cause pinned.

**Fix outline.** Investigation-first. Bisect leaky suite, examine env vars, choose surgical teardown vs broader `run_suite()` hermeticity.

**Complexity:** Unknown. **Action now:** /investigate #594 — bug-with-unclear-cause triage bucket. Persistent skip across cron fires until root cause is established.

### #624 — All 5 /land-pr callers miss the same 3 STATUS values in case statement (5-skill family)

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `/land-pr` documents 12 STATUS values (`skills/land-pr/SKILL.md:158`). All 5 caller skills (`commit/modes/pr.md`, `do/modes/pr.md`, `fix-issues/modes/pr.md`, `quickfix/SKILL.md`, `run-plan/modes/pr.md`) explicitly enumerate 9 in their case statements but silently fall through on `behind-thrash`, `auto-rebase-conflict`, `auto-rebase-blocked` (no `*)` default arm). `references/caller-loop-pattern.md` (the canonical pattern documented by /land-pr) covers only the same 9. The auto-rebase-blocked path is hit in real life (per memory anchor [[feedback_automerge_blocked_means_act]]). Most concerning: `/commit pr` then writes `fulfilled.commit.<id> status: complete` — a SUCCESS marker for a failure-class outcome.

**Fix outline.** (a) Update `references/caller-loop-pattern.md` to add the 3 missing STATUS arms + a `*)` default that maps to `pr-ready` or surfaces unknown loudly. (b) Mirror the fix to all 5 caller skills' case statements. (c) Conformance pin in `tests/test-skill-conformance.sh` (or similar) asserting each of the 5 callers' case statements name all 12 STATUS values (mirror-of-existing-pattern from #602's case-arm pin). (d) Bump `metadata.version` on each affected skill + mirrors.

**Complexity:** M (5 caller-skill edits + reference doc + conformance pin + 5 version bumps + 5 mirrors). **Action now:** /do pr — apply the case-statement extension to all 5 callers per the canonical pattern.

### #621 — /briefing #516 closure-incomplete: landed-pr-merged-but-diverged invisible in summary / Needs Attention / worktrees-mode

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** PR #532 (#516 fix) added the `landed-pr-merged-but-diverged` category at the worktree-removal gate but never wired it through the 3 briefing renderer paths: summary-mode pill list (briefing.py:1080-1100) enumerates 7 categories, missing `landed-pr-merged-but-diverged` and `landed-partial`; report-mode "Needs Attention" section (briefing.py:1155-1210) lists 3 needs-attention categories, missing `landed-pr-merged-but-diverged`; worktrees-mode bucketing similarly silent. Producer writes the marker; renderers don't consume it. Same vocab-drift family as #602 (closed) and #618 (open) on different surfaces (BASH, JS, PYTHON respectively).

**Fix outline.** Update briefing.py to add the missing categories to (a) summary-mode pill enumeration, (b) report-mode Needs Attention category list, (c) worktrees-mode bucketing. Conformance pin asserting every CANONICAL_STATUSES value appears in each renderer enumeration (mirror-of-existing-pattern from #602's case-arm pin, adapted to Python).

**Complexity:** S (briefing.py renderer updates + conformance pin + version bump + mirror). **Action now:** /do pr — wire the missing categories through the 3 renderer paths and add the structural enumeration pin.

### #618 — /zskills-dashboard landedPillClass only maps 2 of 9 documented .landed statuses (Mirror of #602 in JS surface)

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `skills/zskills-dashboard/scripts/zskills_monitor/static/app.js:1003-1008` `landedPillClass()` maps only `full` and `partial` to colored pills; the other 7 documented .landed statuses (`landed`, `pr-ready`, `pr-ci-failing`, `pr-failed`, `conflict`, `pr-state-unknown`, plus the failure-class trio `failed`/`direct-push-failed`/`direct-verify-failed`) silently fall through to the grey "not-landed" pill — visually identical to a worktree with NO `.landed` marker at all. Same vocab-drift family as #602 (closed, BASH surface), #621 (closed, PY renderers).

**Fix outline.** Extend `landedPillClass(status)` to cover all 9 canonical statuses, mapping each to the appropriate visual class (green for `full|landed`, orange for `partial|pr-ready`, red/attention for failure-class). Add CSS classes if needed. Conformance pin asserting each of the 9 canonical statuses has a mapping (mirror #602's per-status loop pattern adapted to JS source).

**Complexity:** S (one JS function + maybe CSS additions + conformance pin + version bump + mirror). **Action now:** /do pr — extend landedPillClass + add per-status conformance pin.

### #584 — /review-feedback skill is block-diagram-specific but lives under skills/ root

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `skills/review-feedback/SKILL.md` is block-diagram-editor-specific (references "Feedback Panel > History > Export JSON", `src/io/FeedbackStore.js` import path, body template `### Context` section with `Blocks`/`Solver`/`ode45` domain vocabulary) but lives under `skills/` (the project-agnostic framework tree). The block-diagram tree (`block-diagram/`) already houses 3 add-ons (add-block, add-example, model-design). CLAUDE.md's Architecture section explicitly separates the two.

**Fix outline.** Move `skills/review-feedback/` → `block-diagram/review-feedback/` (and mirror `.claude/skills/review-feedback/` → `.claude/skills/review-feedback/` if the mirror tree shares structure). Update CLAUDE.md / SKILL_AUDIT_COVERAGE.md / any release scripts that enumerate skill paths. Bump metadata.version. Verify all tests + mirrors still pass.

**Complexity:** M (directory move + several path reference updates + version bump + mirror + verify nothing in build/release scripts hardcodes the old path). **Action now:** /do pr — `git mv` the skill, update path references, verify tests.

### #581 — Add auto flag + /land-pr dispatch to /draft-plan, /refine-plan, /draft-tests

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** 3 drafting skills create worktrees but provide no auto-landing path. Under `execution.landing: pr` + `main_protected: true`, the canonical `/draft-plan → /run-plan` flow silently fails because `/run-plan` reads `$MAIN_ROOT/$PLAN_FILE` but the plan was only committed in the draftplan worktree. User must manually file a small PR before invoking `/run-plan`.

**Fix outline.** For each of `/draft-plan`, `/refine-plan`, `/draft-tests`: (a) recognize positional `auto` token in Arguments parse (mirror existing /do, /run-plan, /fix-issues convention); (b) at Phase 6 (or equivalent auto-commit phase), when AUTO_FLAG=1, dispatch `/land-pr` via Skill tool with `--auto`. Canonical pattern reference: `skills/quickfix/SKILL.md:1084-1107`. Conformance pin asserting each of the 3 skills has the auto-arg detection + /land-pr dispatch line.

**Complexity:** M (3 skill source + 3 mirrors + 3 version bumps + 1 conformance pin). **Action now:** /do pr — apply the auto + /land-pr dispatch to all 3 drafting skills + conformance pin.

### #638 — scripts/skill-version-stage-check.sh fallback masks 'bump-on-disk-not-staged' case

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `scripts/skill-version-stage-check.sh` lines 105-107 substitutes on-disk version into `$staged_ver` when SKILL.md isn't staged. When SKILL.md HAS been bumped on disk but NOT staged, the fallback masks the bug — asymmetric check sees `staged_ver != head_ver` and is skipped; the hint code becomes unreachable. Result: a commit lands with stale RECORDED `metadata.version` + new content (bump-on-disk-not-staged silent pass).

**Fix outline.** Distinguish "child file staged, SKILL.md genuinely unchanged" from "SKILL.md bumped on disk but not staged". Check if `git diff SKILL.md` (working-tree-vs-HEAD) shows changes when SKILL.md isn't staged — if yes, that's the bump-not-staged case and should FAIL CLOSED with the canonical bump command. Add a test case to `tests/test-skill-version-stage-check.sh` (or wherever the script's tests live) for the bump-not-staged scenario.

**Complexity:** S (one script edit + one test case + update-zskills version bump + mirror). **Action now:** /do pr — fix the fallback to distinguish bump-not-staged from genuinely-unchanged-skill-md; add test case.

### #649 — CLAUDE.md Architecture skill counts stale (18+3 → actual 25+4)

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** `CLAUDE.md` lines 9-10 claim `skills/` has 18 core skills and `block-diagram/` has 3 add-ons. Ground truth: 25 core + 4 add-ons (per `ls -d skills/*/ | wc -l` and `ls -d block-diagram/*/ | grep -v screenshots | wc -l`). 8-skill drift; the +1 add-on came from #584's git mv of /review-feedback.

**Fix outline.** Update CLAUDE.md lines 9-10 to read "25 core" and "4 add-ons". Single-file doc edit, no code touched. Optional: add a conformance pin asserting the counts match `ls -d` output (mirror-of-existing-pattern from prior count pins).

**Complexity:** S (one CLAUDE.md edit + optional conformance pin). **Action now:** /do pr — fix the two count strings; consider adding a pin so drift is caught structurally next time.

### #648 — Parent-side `auto` propagation family: 3 dispatch sites lose `auto` (closure-incomplete on #581)

**Labels:** (none) | **Verdict:** RESEARCHED

**Problem.** PR #642 (#581 closure) made the 3 drafting skills (/draft-plan, /refine-plan, /draft-tests) recognize `auto` + dispatch /land-pr. But 3 parent dispatch sites still don't propagate `auto` to the children: `skills/research-and-plan/SKILL.md:158` (→/draft-plan, also #646), `skills/run-plan/SKILL.md:904` and `L949` (→/refine-plan), `skills/run-plan/SKILL.md:1146` (→/draft-plan delegate-mode example). Falsifying trace: /research-and-go → /run-plan auto pr → /run-plan detects staleness → /refine-plan invoked WITHOUT auto → refined plan stranded on `refine-plan/<slug>` worktree branch → /run-plan's "re-read the plan and continue" reads the STALE plan on main.

**Fix outline.** Append `auto` to each of the 3 dispatch sites in /research-and-plan + /run-plan SKILL.md. 2 skill source + 2 mirror updates + 2 version bumps. Conformance pin asserting each documented parent-→child dispatch line in research-and-plan + run-plan contains `auto` (loop over the canonical phrases, source + mirror).

**Complexity:** M (2 skill source edits + 2 mirrors + conformance pin + 2 version bumps). **Action now:** /do pr — propagate `auto` at all 3 dispatch sites and add the pin.

### #655 — `/update-zskills` install scope missing `hooks/block-run-plan-unclaimed.sh`

**Labels:** (none) | **Verdict:** NOT FIXED

**Problem.** `hooks/block-run-plan-unclaimed.sh` landed in PR #544 (commit 1fc16c5) as the PreToolUse hook enforcing /run-plan plan-claim invocations. It exists at `hooks/block-run-plan-unclaimed.sh` (9481 bytes, executable) and is wired into this repo's `.claude/settings.json:34`. But `/update-zskills` SKILL.md has zero references to it (verified: `grep -n 'block-run-plan-unclaimed' skills/update-zskills/SKILL.md` → empty). Consumers running `/update-zskills` since 2026-05-21 don't get the hook installed, making the plan-claim contract advisory on their machines. Same install-list-omission class as #505 (closed 2026-05-21).

**Fix outline.** Two-surface edit to `skills/update-zskills/SKILL.md` (mirroring existing `block-fix-issue-unclaimed.sh`):

1. Step C copy list (after line 1134): add a copy-block entry for `block-run-plan-unclaimed.sh` with descriptive prose explaining what it gates (plan-claim PreToolUse on Bash).
2. Canonical-triples table (after line 1248): add a `PreToolUse | Bash | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-run-plan-unclaimed.sh"` row.

Plus a structural conformance pin in `tests/test-skill-conformance.sh` (or new test): assert every `hooks/block-*.sh` is referenced in `/update-zskills` SKILL.md install list — terminates the family at CI time, preventing instance #3.

**Complexity:** S. **Action now:** /fix-issues — 2-surface SKILL.md edit + ~10-line conformance test; body is verification-anchored and all line refs verified against current main.

### #682 — Decision-table prose trains agents to see /quickfix vs /do as size hierarchy — reframe as worktree-vs-main (the real distinction)

**Labels:** (none) | **Verdict:** NEEDS FIX

**Problem.** The "Which skill for which input" decision table in `CLAUDE_TEMPLATE.md` (and the rendered `.claude/rules/zskills/managed.md`) describes `/do` as "Ad-hoc task ... larger than `/quickfix`," and the "Common confusions" subsection reinforces a size-based framing ("/quickfix is the FLOOR ..."). The real structural distinction between the two skills is worktree-vs-main, not size — and in this repo (`main_protected: true`), `/quickfix`'s in-place-on-main checkout is structurally inappropriate. Agents repeatedly propose `/quickfix` here as "the lighter option," which the user catches every time at proposal time.

**Fix outline.** In `CLAUDE_TEMPLATE.md`, reframe the two table rows (lines 303 and 306) to key on worktree-vs-main (and project policy) rather than task size, and rewrite the "Common confusions" `/quickfix` vs `/do` bullet (line 319) to state explicitly that they are PEERS, not TIERS — same lifecycle, same /land-pr dispatch, same one-commit-PR shape; pick by `main_protected` policy, not size. Run `/update-zskills --rerender` to refresh `.claude/rules/zskills/managed.md` (the duplicated copies at managed.md lines 303/306/319 follow automatically). Add 2-3 conformance pins to `tests/test-skill-conformance.sh` (positive: "PEERS, not TIERS"; positive: "pick by ... project policy ... not task size"; negative: no "larger than `/quickfix`" phrasing) using the existing `check_in_file` / inverted helpers around line 94/161.

**Complexity:** S. **Action now:** /quickfix — reframe CLAUDE_TEMPLATE.md decision-table rows + Common-confusions bullet to peers-not-tiers, rerender managed.md, add 3 conformance pins (peers-not-tiers, pick-by-policy, negative-pin on old phrasing).

### #681 — /qe-audit + /fix-issues: prescribe `## Files to change` section in issue bodies + enforce implementer scope-grep — closes #629/#649 closure-incomplete pattern at framework level

**Labels:** (none) | **Verdict:** NEEDS FIX

**Problem.** Recurring closure-incomplete pattern observed across passes 26 + 33 + 36: `/fix-issues` implementers read the title + headline file mentions but don't systematically grep the issue body for additional file paths. Documented misses: #629 (PR #626 fixed 4 body siblings of #606 but missed 2 added via comments) and #649 (PR #651 fixed `CLAUDE.md` per the title but missed `.zskills/issues/SKILL_AUDIT_COVERAGE.md` named in the body). Each instance cost an extra audit pass + comment + inline-fix. The defect class is real and recurring; framework-level fix removes it.

**Fix outline.** Three coordinated edits across two skill files and one test file: (1) `skills/qe-audit/SKILL.md:247-282` Step 6 — prescribe that every filed issue body include a `## Files to change` section near the top as the authoritative scope (even single-file fixes get a one-bullet list); (2) `skills/fix-issues/SKILL.md:2280-2337` agent-dispatch-prompt template — append a "Before declaring done, verify scope" directive that greps the issue body for `## Files to change`, then verifies each listed path appears in `git diff origin/main..HEAD --name-only`; (3) `tests/test-skill-conformance.sh` — add 3 pins (qe-audit prescribes "Files to change", fix-issues impl-prompt greps for it, fix-issues impl-prompt verifies via `git diff --name-only`). The issue body itself dogfoods the prescribed format. Plus required `metadata.version` bumps on both edited skills (per skill-versioning enforcement).

**Complexity:** S. **Action now:** /quickfix — Add `## Files to change` prescription to qe-audit Step 6, append scope-grep verification to fix-issues impl-prompt, add 3 conformance pins; bump both skill metadata.version stamps.

### #660 — Skill-layer gap: `/work-on-plans` and `/fix-issues` need column-targeted `add/rank/remove` (only `plans.ready` is programmatically mutable; issues queue has no skill affordance at all)

**Labels:** (none) | **Verdict:** NEEDS FIX

**Problem.** `/work-on-plans`'s `add`/`rank`/`remove` helpers hardcode `"ready"` — at `skills/work-on-plans/SKILL.md:948` (`ready = plans.setdefault("ready", [])`), `:995` and `:1006` (rank), and `:1030`/`:1036` (remove) — with no `[column]` arg, so `plans.drafted` and `plans.reviewed` can only be mutated via UI drag or raw `POST /api/queue`. `/fix-issues` has no `add`/`rank`/`remove` subcommands at all (grep of `skills/fix-issues/SKILL.md` shows only `sync`/`plan`/`stop`/`next`/`now`/sprint entry points), so `issues.{triage,ready,backlog}` columns have zero skill-layer mutation affordance. The gap is observable: operators wanting to enqueue a GitHub issue must hand-roll `curl /api/state | python3 ... | curl -X POST /api/queue` against the dashboard.

**Fix outline.** (A) Generalize `/work-on-plans` Step 7 helpers (`skills/work-on-plans/SKILL.md:926-1044`): add optional `[column]` positional between `<slug>` and `[pos]`, defaulting to `"ready"` (backward-compatible), validate against `{drafted, reviewed, ready}`, replace literal `"ready"` keys with the parameter. (B) Add a parallel Step 7-equivalent block to `skills/fix-issues/SKILL.md` exposing `add <N> [column] [pos]`, `rank <N> [column] <pos>`, `remove <N> [column]` against `issues.{triage,ready,backlog}` (default `ready`), validating `<N>` is an integer and `gh issue view <N>` returns OPEN. Optionally extract the shared Python flock+atomic-write helper to `skills/zskills-dashboard/scripts/queue-mutate.py` taking `--kind {plans|issues} --column <NAME>`. Mirror copies under `.claude/skills/{work-on-plans,fix-issues}/SKILL.md`, bump both `metadata.version` fields, and add conformance pins + behavioral tests (column-validation rejection, flock contention, round-trip).

**Complexity:** M. **Action now:** /draft-plan — plan-scale design surface; needs adversarial plan review before any fix.

### #675 — Dashboard: add scroll affordance for the below-band (discoverability)
**Labels:** none | **Verdict:** actionable enhancement
**Problem.** The Plans and Issues panels render active columns (Drafted/Reviewed/Ready, Triage/Ready) above a below-panel band (Backlog/Discarded/Completed). When the active row has many entries (10+), the below-band is pushed off-screen on a 1080p viewport. Users who don't know it exists never discover it --- defeating the purpose of plan #650's Backlog/Completed feature.
**Fix outline.** Add a pinned mini-nav strip (pill-style: `[Active 10] [Backlog 14] [Completed 3]`) at the top of each panel inside `renderPlans()` and `renderIssues()`. Each pill shows a live count from `lastGoodQueues` and, on click, calls `scrollIntoView({ behavior: "smooth" })` on the target section. If the target column is collapsed (PR #668 machinery), call `applyCollapseStateToColumn(colDiv, kind, col, false)` first to expand it, then scroll. CSS: sticky-position the strip so it remains visible during scroll. Affected files: `skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` (inject nav strip in renderPlans ~L985 and renderIssues ~L1310, wire click handler), `skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` (`.section-nav-strip` sticky positioning + pill styling). Tests: add 3 static-grep tests to `tests/test_zskills_monitor_dashboard_ui.sh` (nav pills exist, scrollIntoView wired, expand-before-scroll coordination). Skill version bump for `zskills-dashboard`.
**Complexity:** S. **Action now:** /do pr --- add section-nav pill strip to Plans + Issues panels for below-band discoverability

### #676 — Dashboard: add UI control for completed-window (7d/14d/30d/90d/all)
**Labels:** (none) | **Verdict:** actionable
**Problem.** The Completed column filters plans/issues by `execution.dashboard_completed_days` (default 14d). Plans completed >14 days ago are invisible everywhere — not rendered on the dashboard at all. The server-side `_infer_default_column` returns `None` for out-of-window plans, and the client (`deepCloneQueues` line 535) correctly skips `null`-column plans. Users who want to see older history must edit `zskills-config.json` and restart. After PR #658 backfill, 23 historical plans fell outside the window and vanished.
**Fix outline.** Two-layer change: (1) **Server side** (`collect.py`): `_infer_default_column` and `_infer_issue_default_column` currently return `None`/hide for out-of-window completes — change to ALWAYS return `"completed"` (remove the window cutoff from inference), so ALL completed plans/issues are included in the snapshot payload. The snapshot already carries the `completed:` / `closed_at` timestamp per plan/issue, giving the client enough data to filter. (2) **Client side** (`app.js`): Add a `<select>` dropdown in the Completed column header (inside `renderBelowPanelBand` at the `head` element for the `completed` column, alongside the existing collapse toggle). Options: 7d, 14d (default from config), 30d, 90d, All. Persist choice to `localStorage` using the existing `zskills:dashboard:` prefix scheme (key: `zskills:dashboard:completed-window:<kind>`). In `deepCloneQueues`, apply the client-side window filter: compare each plan's `completed` timestamp (or issue's `closed_at`) against the selected window, skipping plans outside the window instead of the current `!col` skip. The `dashboard_completed_days` config value becomes the default for users with no localStorage preference. Skill version bump required. ~80-120 lines of production code + 3 tests (dropdown renders, localStorage filter works, config fallback).
**Complexity:** M. **Action now:** /do pr — add completed-window dropdown to dashboard Completed column header with localStorage persistence and client-side filtering

### #674 — Dashboard: add ZSKILLS_DASHBOARD_ROOT opt-in override for worktree-rooted verification
**Labels:** (none) | **Verdict:** Mostly fixed, issue left open — SKILL.md surface not updated
**Problem.** `resolve_main_root()` always anchors to the main checkout, so agents in worktrees running `/zskills-dashboard restart` see stale UI from main instead of their worktree changes. Blocks visual verification of frontend work.
**Fix outline.** The Python-level fix already landed in PR #698 (commit `a99a6db`): `ZSKILLS_DASHBOARD_ROOT` env-var override in `collect.py:_resolve_main_root`, `--main-root` CLI flag in `server.py`, and 3 tests in `test_zskills_monitor_collect.sh`. The remaining gap is that `skills/zskills-dashboard/SKILL.md` does not document the env var or expose a `--root` flag in its start-mode bash block — agents won't discover the override unless they read server.py directly. Close the issue by: (1) adding `ZSKILLS_DASHBOARD_ROOT` / `--root` documentation to the SKILL.md start block, (2) bumping skill version, (3) mirroring to `.claude/skills/`, (4) closing #674.
**Complexity:** S. **Action now:** /do pr — document ZSKILLS_DASHBOARD_ROOT and --root flag in zskills-dashboard SKILL.md, bump skill version, close #674

### #672 — backfill-plan-completed.sh: ${CLAUDE_PROJECT_DIR} unbound under set -u
**Labels:** (none) | **Verdict:** actionable — clear one-line bug with fix sketch in issue
**Problem.** `skills/zskills-dashboard/scripts/backfill-plan-completed.sh` line 84 dereferences `$CLAUDE_PROJECT_DIR` under `set -euo pipefail` (line 47). When the variable is unset (standalone shell invocation outside Claude Code), bash exits with "unbound variable" before the `||` fallback block on lines 84-89 can execute. The `.claude/skills/` mirror has the identical bug.
**Fix outline.** Replace line 84's bare `$CLAUDE_PROJECT_DIR` with a default-substitution form: `. "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/skills/update-zskills/scripts/zskills-paths.sh" 2>/dev/null || {`. Both source and mirror need the fix. Bump `zskills-dashboard` skill version. Add a test case that invokes the script with `CLAUDE_PROJECT_DIR` unset and asserts no "unbound variable" error (no existing test file found — may need a new `tests/test-backfill-plan-completed.sh`).
**Complexity:** S. **Action now:** /do pr — fix default-substitution on line 84 in source + mirror, add unbound-variable test, bump skill version

### #700 — Dashboard: polish collapse/expand toggle, collapsed-column preview, and column-move chevrons
**Labels:** none | **Verdict:** actionable — CSS+JS cosmetic polish, scope well-defined
**Problem.** Three below-band UX polish items: (1) collapse toggle (`▸`/`▾`) is too small at `font-size: 0.9em` + `padding: 0 0.2em` — reads as a dot, not a button; (2) collapsed columns hide the dropzone (`display: none`) but show nothing in its place — looks broken rather than intentionally collapsed; (3) move-all chevrons (`«`/`»`) have minimal styling (`padding: 0 6px`, `border-radius: 4px`) inconsistent with the section-nav pills and other action buttons that use `border-radius: 999px`, hover transitions, etc.
**Fix outline.** All changes in two source files: `skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` and `app.js` (mirror copies to `.claude/skills/` after). (1) Increase `.column-collapse-toggle` to `font-size: 1.1em`, `padding: 2px 6px`, add `border-radius: 4px` and a subtle background on hover. (2) In `applyCollapseStateToColumn` (JS ~L137), when collapsed, inject a compact summary strip into `colDiv` showing "Label (N)" with first 1-2 card titles truncated; in CSS add a `.collapsed-summary` rule for the strip. (3) Style `.move-all-btn` with `border-radius: 6px`, `padding: 2px 8px`, and a `transition: border-color 0.12s, color 0.12s, background 0.12s` matching `.section-nav-pill`.
**Complexity:** S. **Action now:** /do pr — polish collapse toggle size, collapsed-column preview strip, and move-all chevron styling in dashboard CSS+JS

### #717 — Dashboard Branches tab: state pills, status grouping, collapsed sections, bulk copy

**Labels:** (none)

**Problem.** Branches tab is a flat unsorted 147-entry list with no state visibility, grouping, or bulk operations. Four distinct sub-features requested: state pills, status grouping with collapsed sections, bulk copy, and nav strip.

**Fix outline.** JS + CSS changes to app.js and app.css across 4 sub-features: (1) state pill rendering per branch card, (2) three-section grouping with collapse toggle, (3) select-all + copy button per section, (4) nav strip with counts. Each sub-feature is independently testable but they share DOM structure.

**Complexity:** L. **Action now:** /draft-plan — plan-scale: 4 distinct UI sub-features with shared DOM structure; needs design review before implementation.

### #716 — /cleanup-merged redesign: preview-default, positional tokens, remote cleanup, protected branches

**Labels:** (none)

**Problem.** /cleanup-merged is destructive-by-default, uses --flags instead of positional tokens (breaking repo convention), has no remote branch cleanup, and no branch exclusion mechanism.

**Fix outline.** Redesign skill interface: preview-default mode, positional apply/remote/all tokens, gh-pr-view-gated remote deletion, protected_branches config field. Touches SKILL.md prose + possibly helper scripts.

**Complexity:** L. **Action now:** /draft-plan — plan-scale: full skill interface redesign with 4 distinct behavioral changes + new config field.

### #720 — /fix-issues research agent over-classifies detailed issue bodies as plan-scale
**Labels:** (none) | **Verdict:** actionable-do-pr
**Problem.** The Phase 2 triage rubric's `plan-scale` bucket is triggered by long/detailed issue bodies (multiple sections, design tables, proposed interfaces) even when the design is already locked and implementation is straightforward. A detailed spec is the opposite of plan-scale — the design work is already done. Observed: #716 (one SKILL.md rewrite) and #717 (app.js/css following existing pattern) both skipped as plan-scale despite being /do-scale.
**Fix outline.** Add a counter-signal paragraph to the `plan-scale` bullet in `### Triage: vague, complex, or interrelated issues` (line ~1993 of `skills/fix-issues/SKILL.md`). The counter-signal: if the issue body contains a locked design (proposed interface, specific file locations, explicit scope section, worked examples), weight this AGAINST plan-scale classification — a detailed spec means design work is done, so classify as actionable unless it touches 3+ skills or requires new infrastructure. Mirror change to `.claude/skills/fix-issues/SKILL.md` + skill-version bump via `scripts/skill-content-hash.sh`.
**Complexity:** S. **Action now:** /do pr — add counter-signal prose to plan-scale bucket in fix-issues triage rubric (~5 lines), mirror + version bump

### #721 — /fix-issues: split 'needs-decision' skip category into 'needs-decision' vs 'deferred'
**Labels:** (none) | **Verdict:** ACTIONABLE
**Problem.** The `needs-decision` skip classification conflates two semantically opposite outcomes: issues genuinely awaiting human input ("which approach?") and issues the agent decided to park ("leave open as architectural memo"). Both show the same pink/magenta chip on the dashboard, making `needs-decision` misleading — it implies action required when the agent verdict may be "no action now." Example: #67 (GitLab support) shows `skip: needs-decision` but is deferred pending prerequisites, not awaiting a decision.
**Fix outline.** Introduce a new `deferred` skip-code alongside `needs-decision`. Touch points:
1. `skills/fix-issues/SKILL.md` — Phase 2 six-bucket rubric: split `needs-decision|author-decision` case into `needs-decision` (genuinely needs human input) vs `deferred` (agent decided no action); update both the triage enum (~L2150, L2755) and the two `case "$CLASS"` blocks (~L2759, L3010) plus the A+F write-back blocks (~L2777, L3027) to emit `**Action now:** deferred — <reason>` for the new code.
2. `skills/fix-issues/scripts/filter-unresearched-candidates.sh` — L95-96: add `deferred` to the SKIP output logic (currently `Action now: none` -> `SKIP=needs-decision`; split: `none — author decision` -> `needs-decision`, `none — deferred/waiting/leave open` -> `deferred`).
3. `skills/zskills-dashboard/scripts/zskills_monitor/collect.py` — `_classify_skip_reason()` (~L1888): add `deferred` code branch for action-now values matching deferred patterns; keep `needs-decision` for genuine decision-needed.
4. `skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` — add `.skip-chip--deferred` with grey/dim styling (distinct from magenta `needs-decision`).
5. `skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` — chip renderer already class-names by code; no change needed unless label formatting differs.
6. Tests: update `tests/test-issues-skip-reason-parse.sh` (synthetic #100, real-tracker #67/#432 expectations) and `tests/test-fix-issues-phase2-source-filter.sh` (#703 expected output) to cover both codes.
7. Mirror `.claude/skills/` copies + skill-version bumps for `fix-issues` and `zskills-dashboard`.
**Complexity:** M. **Action now:** /do pr — split needs-decision skip-code into needs-decision vs deferred across fix-issues rubric, filter script, dashboard collect.py, CSS chip, and tests

### #729 — 6c78aca accidentally reverted /fix-issues `next` staleness step from 3d8e120 — #719 closure-incomplete
**Labels:** (none) | **Verdict:** actionable — mechanical restoration of accidentally-reverted prose
**Problem.** Commit 6c78aca (#728, closing #720) overwrote the `next` subcommand's staleness step (lines 466-475) that 3d8e120 (#723, closing #719) had just added. On HEAD, line 469 is a bare `4. **Exit.** Do not proceed to any phase.` — the "Peek at the Ready queue" block that reports staleness from `.zskills/monitor-state.json` is gone. An agent running `/fix-issues next` with an empty Ready queue silently exits without surfacing staleness info. Second instance of the same accidental-revert pattern (#704 was the first).
**Fix outline.** Restore the staleness step from 3d8e120 before the `**Exit.**` line at SKILL.md:469 in the `next` section. The block adds steps 4 (peek at Ready queue, report count or staleness) and renumbers Exit to step 5. Bump `metadata.version`. Mirror source to `.claude/skills/fix-issues/SKILL.md`. Two files changed, zero logic — pure prose restoration.
**Complexity:** S. **Action now:** /do pr — restore accidentally-reverted staleness step in /fix-issues `next` section from 3d8e120 + version bump + mirror


### #839 — /session-report handoff mode — durable hand-off
**Labels:** (none) | **Verdict:** ACTIONABLE
**Problem.** `/session-report` only does a retrospective audit (Steps 1-4: enumerate session intent, verify against ground truth, reconcile, report). There is no way to produce a durable end-of-session hand-off near full context: capturing in-flight concerns, pending work, resume-context, plus a `/clear`-vs-`/compact` recommendation and a copy-paste post-`/clear` kickoff prompt. A real session (plugin-launch → PR #831) had to do this entirely by hand at ~93% context.
**Fix outline.** Add a new mode file `skills/session-report/modes/handoff.md` (~50-100 lines) holding the forward-capture procedure, then add arg-detection + a Read-dispatch line in `skills/session-report/SKILL.md` so `/session-report handoff` Reads the mode file on demand — same idiom as `/run-plan`'s `## Subcommands` table (SKILL.md:284-296) Read-dispatching into `subcommands/` and `modes/execute-phase.md`. Reuse the existing Steps 1-3 audit verbatim for the "work done" summary; the mode adds forward capture (in-flight concerns, pending fixes/plans, open questions, resume-context), persistence (write a `project_*` memory file + one-line MEMORY.md pointer per CLAUDE.md Memory section), and a ready-message (work summary + `/clear`-vs-`/compact` heuristic + kickoff prompt). Update `argument-hint` (currently `""`, SKILL.md:3) to advertise `[handoff]`, bump `metadata.version` (currently `2026.05.21+a6f97e`, SKILL.md:10) via `scripts/skill-content-hash.sh`, and mirror the whole skill dir to `.claude/skills/session-report/` (mirror currently has only SKILL.md). Keep the default lean (progressive disclosure — a plain `/session-report` loads zero handoff prose); the posture-fork (forward-looking capture lives entirely in the mode file, the default audit stays pure-retrospective: "Do not invent next actions," "Verify, don't recall") is the one design note to honor.
**Complexity:** S-M. **Action now:** /do pr — add handoff mode via progressive disclosure (new mode file + arg-detection + version bump + mirror).

### #836 — /quickfix: extract phases into mode/reference files
**Labels:** (none) | **Verdict:** ACTIONABLE
**Problem.** `skills/quickfix/SKILL.md` is 1533 lines (current `metadata.version: 2026.05.31+1fd7b7`) — the second-largest non-decomposed skill, with no `modes/`/`references/`/`scripts/` dirs. Every invocation loads the whole file even though each fire follows one of two runtime-branched modes (user-edited vs agent-dispatched) sharing the Phase 1–7 lifecycle. Same context-window concern as #724/#725/#726 and the parallel `/draft-tests` proposal.
**Fix outline.** Split the body around the Phase-2 mode-detection boundary the router needs before it can dispatch: keep modes intro + coexistence + arg parser + Phase 1 pre-flight + Phase 2 mode detection/slug in `SKILL.md` (~775-line router); extract Phase 3 make-the-change + Phase 4 test gate + Phase 5 commit + Phase 5.5 verify + Phase 6 push to `modes/execute.md` (~330 lines); extract Phase 7 PR creation + CI poll + `/land-pr` fix-cycle to `modes/land.md` (~400 lines); move Exit codes + Key Rules to `references/exit-codes-and-rules.md` (~50 lines). Router prose: "after Phase 2, read `modes/execute.md` then `modes/land.md`." Mirror the split into `.claude/skills/quickfix/`, bump `metadata.version`, and chase stale `SKILL.md:NNN` cross-refs — live ones at `skills/commit/modes/pr.md:95` and `skills/do/modes/pr.md:278` (both cite `quickfix/SKILL.md:634`) plus their `.claude/skills/` mirrors. Conformance tests (`test-quickfix.sh`, `test-skill-conformance.sh`, `test-skill-invariants.sh`) reference quickfix by path + content-grep anchors (e.g. `MARKER="$TRACK_DIR/fulfilled.quickfix.$SLUG"`), NOT by hardcoded line numbers, so they survive the split as long as the grep'd literals move intact with their phase — but they must still be re-run, since some grep targets are file-scoped to `SKILL.md` and would need to point at the new mode files if that content relocates.
**Complexity:** M. **Action now:** /do pr — mechanical phase-extraction refactor; trace the shared-variable flow (slug, branch name, tracking ID/PIPELINE_ID + EXIT trap, commit metadata, PR_URL, CI status) across Phases 3–7 before splitting since it is denser than `/fix-issues`' subcommand split — partial split (just `modes/land.md`) is the acceptable fallback if the variable graph proves too entangled.

### #853 — Dashboard: auto-route status:complete + completed: plans to the Completed column, overriding pins

**Labels:** (none) | **Verdict:** NOT FIXED

**Problem.** `collect.py:_annotate_plans_queue` (L1772-1781) builds a slug→position lookup from `monitor-state.json` and short-circuits to the pinned column whenever a slug is present, never consulting plan frontmatter. The docstring at L1733-1736 explicitly documents this as W1.3/D2 rule (i): "state-file explicit-position WINS over inference — a plan present in the state file's `backlog` (or `drafted`, etc.) stays there even if `status: complete` would otherwise infer `completed`." The plan-file-is-source-of-truth routing exists in `_infer_default_column` at L1582-1587 (`status in ("complete","landed")` + parseable `completed:` → `"completed"`) but is unreachable for any pinned plan. Observed live: `docs/plans/claim-work-item.md` has `status: "complete"` + `completed: "2026-05-30T00:49:15Z"` (PR #825 landed) yet sits in DRAFTED because `monitor-state.json.plans.drafted` contains its slug. No UI affordance to unstick (Completed is not a drop target, rejected at `server.py:459-466`). No test covers the override case.

**Fix outline.** Primary (sufficient): in `_annotate_plans_queue`, before consulting the `pos` lookup, check the plan's `status` + `completed:` frontmatter — if `status in ("complete","landed")` AND `_parse_iso_utc(completed)` succeeds, bypass the pin and route via `_infer_default_column` (which already returns `"completed"`). Auto-heals every stuck plan on next poll. Secondary (nice-to-have): UI/server guard letting users drag complete/landed plans to Completed as an explicit pin-clear, while keeping the column unreachable for non-complete plans. Add a test mirroring W1.20 but asserting the OPPOSITE outcome for `status: complete` + `completed:` pinned plans.

**Complexity:** S. **Action now:** /do pr — add status+completed bypass before pos-lookup in `_annotate_plans_queue` (collect.py ~L1772), add regression test mirroring W1.20 with inverted assertion, mirror to `.claude/skills/zskills-dashboard/` + skill-version bump.

### #852 — Tracking fences write a flat marker silently when PIPELINE_ID is empty (no fail-loud guard)

**Labels:** bug | **Verdict:** NOT FIXED

**Problem.** The `sanitize-pipeline-id.sh` helper already exits 2 on empty input (commit 7f7d3de, closes #468), but the tracking-fence call-sites invoke it as `PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")`. If the preceding resolver-source line fails (e.g. `$CLAUDE_PLUGIN_ROOT` and `$CLAUDE_PROJECT_DIR` both unset, as observed by the issue reporter during dogfooding), `$ZSKILLS_SKILLS_ROOT` is never set, the bash invocation hits a bad path and exits non-zero, command-substitution captures empty stdout, and `PIPELINE_ID=""`. The fences then proceed to `mkdir -p "$MAIN_ROOT/.zskills/tracking/"` and `printf ... > ".../tracking//fulfilled.<skill>.<id>"` — a silent flat write that violates the per-pipeline-subdir invariant (CLAUDE.md → Tracking markers: "never flat under `.zskills/tracking/` directly") and trips the dedup hook on subsequent runs. Affected fence sites (no `[ -n "$PIPELINE_ID" ]` guard between the cmd-substitution and the mkdir/printf): `skills/draft-plan/SKILL.md:193-197,294,497,758,762`; `skills/draft-tests/modes/draft.md:50-53,240`; `skills/draft-tests/modes/land.md:233,237`; `skills/fix-issues/modes/sync.md:277-278,286,385`; `skills/fix-issues/modes/sprint.md:249-254,519,580-583,627,1343-1346,1388,1430,2356-2359,2371,2409,2427-2430,2499,2584,2748-2751,2788,2810,2817`; `skills/fix-issues/modes/pr.md:64-65,88,323,360`; `skills/fix-issues/modes/plan.md:69-72`; `skills/commit/modes/pr.md:102`; `skills/do/modes/pr.md:282`; `skills/run-plan/modes/*.md` (parallel pattern).

**Fix outline.** Add the issue's option (a) fail-loud guard immediately after the `sanitize-pipeline-id.sh` cmd-substitution and before any `mkdir`/`printf` write at every fence site: `[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }`. Add option (c) conformance tripwire in `tests/test-skill-conformance.sh` asserting no skill writes `.zskills/tracking/$PIPELINE_ID/` without an immediately-preceding non-empty guard (regex-locate `mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"` and require a `[ -n "$PIPELINE_ID" ]` test within the preceding ~10 lines of the same fence). Defer option (b) (harden the source-line fallback to use `git rev-parse --git-common-dir` when `$CLAUDE_PROJECT_DIR` is unset) — issue body explicitly calls out it has a larger blast radius and should be verified separately. Bump `metadata.version` for every touched skill via `scripts/skill-content-hash.sh` and mirror to `.claude/skills/`.

**Complexity:** M. **Action now:** /do pr — add `[ -n "$PIPELINE_ID" ]` fence-site guard across ~10 skill files (~25-30 fence sites), add conformance tripwire, bump versions, mirror.

### #858 — /work-on-plans: dashboard shows phase-mode copy-and-run while a finish-mode batch is actually running

**Labels:** (none) | **Verdict:** PARTIALLY FIXED

**Problem.** While a `/work-on-plans N|all finish` batch is running, the dashboard already hides the copy-and-run field (per user 2026-05-31) — the in-flight signal IS plumbed for that one element. Two gaps remain:

- **Default-mode chip not synced + not locked while sprint is in flight.** The chip continues to show the saved `default_mode` (typically `phase`) regardless of the running batch's mode (typically `finish`), and remains user-clickable. While a sprint is in flight, the chip should mirror the **in-flight mode** and be locked — clicking should either no-op or surface a tooltip explaining the lock. Underlying gap is the same as before: `skills/work-on-plans/modes/execute.md` writes `state: sprint` without a `batch_mode` field, so `collect.py` has no in-flight mode to publish, and `app.js` falls back to `lastGoodDefaultMode` for the chip rendering.
- **"Default mode: …" block shifts oddly UX-wise when the "Sprint in flight: change applies to plans not yet dispatched and to future sprints; in-flight plans keep their captured mode." banner appears.** Layout shift looks unintentional and needs polish — likely a CSS/grid-flow issue where the banner pushes the radio group around rather than slotting cleanly above/below.

**Fix outline.** (a) In `execute.md` "Initial sprint state", extend `state: sprint` with `batch_mode` (resolved CLI override or `default_mode` fallback). (b) Extend `collect.py` to read `work-on-plans-state.json` and emit `{running: true, batch_mode, progress}` when `state == sprint`. (c) In `app.js`: when snapshot says running, render the chip in **locked-to-batch-mode** state (show `batch_mode`, disable click, show a tooltip on hover); and restructure the "Sprint in flight" banner placement so the radio group doesn't shift. (d) Verify with `playwright-cli`: dispatch a finish-mode `/work-on-plans` batch, screenshot the chip + banner area, then dispatch a phase-mode batch, screenshot, then idle, screenshot — assert the chip locks/unlocks correctly and the layout doesn't reflow.

Author's open question on concurrent-sprint shape (multi-sprint list vs single-batch ownership guard) is **still open** but doesn't block this polish — the chip-lock + layout fix work against the single-batch state file as it stands; the concurrent-batch design can land separately.

**Complexity:** M. **Action now:** /do pr — chip-lock + layout-shift polish + playwright verification (3 visual states). Concurrent-batch ownership is a separate /draft-plan.

### #861 — test-skill-conformance.sh: add structural existence pins for /draft-tests mode + reference files (mirror PR #849's /quickfix pattern)

**Labels:** (none) | **Verdict:** NOT FIXED

**Problem.** PR #855 split `/draft-tests`'s SKILL.md into a router + 3 mode files + 2 reference files, but added no existence assertions in `tests/test-skill-conformance.sh` for the new structure. The 5 files exist today (`skills/draft-tests/modes/{draft,backfill,land}.md`, `skills/draft-tests/references/{design-constraints,test-spec-format}.md`) but conformance gates them only sideways: `tests/test-skill-conformance.sh:936` lists `skills/draft-tests/modes/land.md` in the `/land-pr` caller array, and `tests/test-skill-invariants.sh:93-94,158-160` carries variable-family allowlist entries for the three mode files — neither asserts existence. `grep -rn 'draft-tests/references' tests/` returns zero hits, so the two reference files have no structural pin at all. This is asymmetric with the just-landed `/quickfix` peer (PR #849, 47 conformance lines pinning `skills/quickfix/modes/land.md` across `tests/test-skill-conformance.sh:933,1013,1034,1087,1135`). If a future refactor deletes or mis-renames any of the 5 files, content that ALSO appears in SKILL.md still passes the `skill_grep` glob (`modes/*.md references/*.md`), leaving partial coverage of the structural invariant.

**Fix outline.** Add a single existence-loop block in `tests/test-skill-conformance.sh` iterating the 5 required files and asserting both the source path (`skills/draft-tests/<rel>`) and the `.claude/` mirror (`.claude/skills/draft-tests/<rel>`) exist, failing closed if any is missing. Mirror the idiomatic style already used by the `/quickfix` pin set. CI-only change; no production-code edits; no skill-version bump (test-only).

**Complexity:** S. **Action now:** /do pr — add 5-file existence-loop pin block in `tests/test-skill-conformance.sh` for `skills/draft-tests/modes/{draft,backfill,land}.md` and `skills/draft-tests/references/{design-constraints,test-spec-format}.md` (plus `.claude/` mirrors), mirroring PR #849's `/quickfix` pattern.

### #863 — Claim arg-parsers acquire only the first #N — a change closing multiple issues leaves the rest grabbable

**Labels:** (none) | **Verdict:** real bug, unfixed

**Problem.** All three claim arg-parsers extract only the FIRST `#N` from the description and acquire one claim. `skills/do/SKILL.md:240-243` does `ISSUE_NUM=""` then `if [[ "$ARGUMENTS" =~ \#([0-9]+) ]]; then ISSUE_NUM="${BASH_REMATCH[1]}"; fi` (BASH_REMATCH captures only the first match). `skills/quickfix/SKILL.md:156-159` has the identical shape against `$DESCRIPTION`. Mode files then propagate the single `$ISSUE_NUM` to `claim-issue.sh acquire/release` in scalar form (e.g. `skills/do/modes/pr.md:117-119`, `skills/do/modes/worktree.md:80-82`, `skills/do/modes/direct.md:27-30`, and the release sites at `skills/do/SKILL.md:900-901`, `skills/do/modes/pr.md:207-215`, `pr.md:336-337`, `pr.md:511-512`). A `/do pr` for `Closes #832, #833` therefore claims only #832, leaving #833 open and grabbable by a concurrent `/fix-issues dashboard` cron (observed this session).

**Fix outline.** Replace the single-capture regex with a loop that extracts every `#N` / `closes #N` / `fixes #N` reference into an `ISSUE_NUMS` array (bash: `while [[ "$rest" =~ \#([0-9]+) ]]; do nums+=("${BASH_REMATCH[1]}"); rest="${rest#*\#${BASH_REMATCH[1]}}"; done`). Update `claim-issue.sh acquire/release` call sites in `skills/do/modes/{direct,worktree,pr}.md` and `skills/quickfix/SKILL.md` to iterate the array (acquire each; on any acquire failure with rc=10 release the already-acquired ones and decline; on resolution release each). `/fix-issues` (#622) is a sprint-mode dispatcher and uses a different per-issue path so it's likely already correct per-issue, but verify the redirect-from-`/do` path passes the full set through.

**Complexity:** M. **Action now:** /do pr — convert ISSUE_NUM scalar to ISSUE_NUMS array in /do + /quickfix arg-parsers, update all acquire/release call sites in mode files, add a unit test that a multi-issue description acquires N claims and releases all N (and that partial-acquire failure rolls back).

### #862 — Dashboard skip-reason chip sourced only from static blurb — diverges from live re-triage + in-flight claim (split-brain)

**Labels:** (none) | **Verdict:** NOT FIXED

**Problem.** The dashboard skip-reason chip and the orchestrator's live skip decision are sourced from two disjoint paths, producing a split-brain whenever they disagree. `collect.py:_build_skip_reason_index` (L2116-2140) parses ONLY `ISSUES_PLAN.md` via `_parse_action_now` (L1944-2070), and `_annotate_issues_queue` (L1858) writes the result to `issue["skip_reason"]` — never consulting `monitor-state.json:issues.skipped` even though `claim_index` is read three lines below at L1859. The orchestrator path is the opposite: `record-skip.sh` writes `monitor-state.json:issues.skipped[N] = "<code>"` and `filter-unresearched-candidates.sh` (header L60-83) reads that map for the Phase-2 drop decision. So when an orchestrator re-triages #832/#833 and records a new code, the filter behavior updates but the chip keeps showing the stale blurb-derived `skip:plan-scale`. Additionally `record-skip.sh` L37 + L63 explicitly accept and then drop a `<reason>` arg ("reserved for future use; not consumed yet"), and `app.js` L1768-1780 renders the skip chip with no mutual-exclusion against the claim chip block at L1791+ — an actively-claimed issue renders both chips simultaneously. The 4-value `plan-scale|bug-unclear-cause|needs-decision|deferred` enum at `record-skip.sh` L73 cannot carry "needs author A/B/C scope decision" precision even when the persisted decision IS consulted.

**Fix outline.** Introduce a single `resolve_effective_skip_reason(issue)` shared by both the Python chip path and the bash filter path with identical precedence: (1) live operational override from `monitor-state.json:issues.skipped[N]` wins when present; (2) fallback to the `Action now:` blurb-derived reason from the tracker. In `collect.py:_annotate_issues_queue`, read `issues.skipped` into a map (mirror the `claim_index` pattern) and consult it BEFORE the `skip_index` lookup at L1892. Extend `record-skip.sh` to actually persist `{code, reason}` (drop the "ignored" comment, store the third arg) and surface `reason` through `skip_reason.label` so the chip can carry author-supplied precision. Add a mutual-exclusion guard in `app.js` so a card with `issue.claim` suppresses the skip-chip block (an in-flight issue is not also a skipped issue). The `reconsider <N>` dual at `filter-unresearched-candidates.sh` L60-83 already removes the override, so naturally resets the chip to its blurb baseline — no new clear-path needed.

**Complexity:** M. **Action now:** /do pr — wire `monitor-state.json:issues.skipped` into `collect.py:_annotate_issues_queue` (mirror the claim_index read at L1859), extend `record-skip.sh` to persist+render the optional `reason` arg, add `claim`-suppresses-`skip_reason` guard in `app.js` L1768, add regression tests asserting (a) live override beats stale blurb (b) claim suppresses skip chip (c) record-skip persisted reason flows through to chip label, bump `metadata.version` on both touched skills, mirror to `.claude/skills/`. Wider question of refactoring the 4-value enum into open-ended `{code, reason}` everywhere is in-scope for this PR since `record-skip.sh` is the single producer.


### #864 — /do pr releases the issue claim at pr-ready (open, unmerged) — issue grabbable until human merge

**Labels:** (none) | **Verdict:** real bug, unfixed

**Problem.** `/do pr`'s explicit-finalize block (`skills/do/modes/pr.md:498-512`) treats `merged`, `created`, and `pr-ready` as success-equivalent and unconditionally releases the issue claim for all three (`bash claim-issue.sh release "$ISSUE_NUM"` at L511-512). But `pr-ready` means the PR is OPEN and NOT merged (`skills/do/modes/pr.md:405-412`, where the `monitored)` arm sets `LAND_OUTCOME=pr-ready` whenever `gh pr view` reports `OPEN`), so the claim drops for the entire unbounded human-review window. `/fix-issues/modes/pr.md:337-342` shows the correct pattern: the `created)` arm explicitly HOLDs the claim with the comment "PR is in flight; claim is released when the PR resolves on a later fire" — `/do pr` lacks this arm because the rationale at `pr.md:506-510` ("/do is one-shot so there is no later fire to re-release") assumed any settle = done. A concurrent `/fix-issues` cron can then re-claim the same issue and duplicate the fix until a human merges the PR (observed: a `/do pr` for #860 released #832/#833 at pr-ready while the PR sat open).

**Fix outline.** Split the `case "$LAND_OUTCOME"` arms in `skills/do/modes/pr.md:498-512` so `merged` releases, `pr-ready`/`created` HOLD with the same in-flight messaging as `/fix-issues/modes/pr.md:341-342`, and `pr-ci-failing`/`rebase-*`/`*-failed` release (terminal failures). Document the one-shot stalled-claim case the same way `/fix-issues` does — claim is reaped manually via `claim-issue.sh release` (the `#684` plan-claim precedent already cited at `fix-issues/modes/pr.md:329-331`). The inline-release sites at `skills/do/modes/pr.md:207-215` (PR_TITLE early-exit) stay unchanged — they are pre-finalize hard failures, not pr-ready settlements.

**Complexity:** S. **Action now:** /do pr — split the `merged|created|pr-ready)` arm in `skills/do/modes/pr.md` into `merged)` (release) + `pr-ready|created)` (HOLD with in-flight log line) + terminal-failure (release), mirror the `/fix-issues/modes/pr.md:337-345` shape, add a unit test asserting `LAND_OUTCOME=pr-ready` leaves the claim file in `.zskills/issue-claims/`, bump `metadata.version` on `do`, mirror to `.claude/skills/`.

### #866 — block-diagram/add-block/SKILL.md: dual-lane resolver prelude sits outside its fence (#831 artifact)

**Labels:** (none) | **Verdict:** real bug, unfixed

**Problem.** Two dual-lane resolver preludes in `block-diagram/add-block/SKILL.md` leak outside any executable fence — a PR #831 migration artifact. Site 1 at `block-diagram/add-block/SKILL.md:567-571` sits immediately after a closing `javascript` fence (L561) inside the numbered list item "3." and before plain prose at L573; there is no `bash` opener so the `if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] ... fi` block renders as markdown prose, not as a runnable block. Site 2 at `block-diagram/add-block/SKILL.md:638-642` sits between a closing `markdown` fence (L637) and the next `### bash` fence at L645 — same defect, also rendered as prose. The #833 inline-prose gate (PR #860) only scans single-backtick code-spans so it does not catch fence-boundary errors of this shape. An agent following the skill body would never source `zskills-resolve-config.sh` at these two sites, leaving `$BLOCK_NAME`/`$BLOCK_SLUG`/`$MAIN_ROOT`/`$PIPELINE_ID`/`$TIMEZONE`/`$ISSUE_NUMBER` unbound when the very next fenced block uses them (`step.add-block.${BLOCK_SLUG}.codegen` at L619 and `step.add-block.${BLOCK_SLUG}.codegen-deferred` at L653).

**Fix outline.** Wrap each leaked prelude in its own ```bash … ``` fence (or merge each into the adjacent bash fence that consumes the resolved variables — Site 1 has no bash neighbour so a standalone fence is cleanest; Site 2 can merge into the L645 fence by deleting the L644 prose-break and the L642 stray `fi`-then-blank-line boundary). Bump `metadata.version` on `block-diagram/add-block/SKILL.md` (per `## Skill versioning`) and mirror to `.claude/skills/add-block/SKILL.md`. Add a conformance check in `tests/test-skill-conformance.sh` for "resolver prelude lines (`. ".../zskills-resolve-config.sh"` or its plugin-lane sibling) appearing outside a `bash` fence" — straightforward awk pass over each skill `.md` tracking fence state.

**Complexity:** S. **Action now:** /do pr — wrap both preludes at `block-diagram/add-block/SKILL.md:567-571,638-642` in `bash` fences (or merge into adjacent fences), bump skill metadata.version, mirror to `.claude/skills/add-block/`, add a `test-skill-conformance.sh` awk gate for resolver-prelude-outside-fence so the next migration cannot regress this.

### #865 — block-fix-issue-unclaimed.sh checks claim existence, not ownership — second pipeline can worktree a claimed issue

**Labels:** (none) | **Verdict:** UNFIXED

**Problem.** `hooks/block-fix-issue-unclaimed.sh:212-215` checks claim presence only — `CLAIM_DIR="${MAIN_ROOT}/.zskills/claims/issue-${NNN}"; if [ -d "$CLAIM_DIR" ]; then exit 0; fi` — and never compares the caller's `--pipeline-id` against `claim.json`'s `pipeline_id`. The hook's shlex-walk at `hooks/block-fix-issue-unclaimed.sh:100-159` extracts `--branch-name` / `--prefix` / positional slug but discards `--pipeline-id`, so the caller identity is on the command line yet thrown away. Result: with pipeline A holding `.zskills/claims/issue-NNN/` (issued by `skills/fix-issues/scripts/claim-issue.sh`, which records `pipeline_id` in `claim.json` per the schema docstring at `claim-issue.sh:39-44`), a *different* pipeline B's `create-worktree.sh --prefix fix-issue NNN --pipeline-id <B>` passes the hook gate and materialises a worktree on the already-claimed issue. Observed live this session per issue body: with `dtsplit` holding the #835 claim, a second pipeline's create-worktree for #835 was not blocked and a stray worktree had to be cleaned up. The fail-closed guard is in name only — only orchestrator adherence to `claim-issue.sh acquire`'s rc=10 race-loss discipline (`skills/fix-issues/scripts/claim-issue.sh` docstring lines 23-25) actually prevents the double-materialise.

**Fix outline.** Extend the shlex walk in `block-fix-issue-unclaimed.sh:100-159` to capture `--pipeline-id <v>` into a third output line (`PIPELINE_ID=<v>`). After the existing `[ -d "$CLAIM_DIR" ]` check at line 213, read `$CLAIM_DIR/claim.json` via Python json, extract `pipeline_id`, and deny (using the same deny-envelope shape at line 245) unless it equals the caller's `--pipeline-id`. Deny on any concrete mismatch; fail-open (with a stderr WARN) only if `claim.json` is absent/malformed — symmetric to claim-issue.sh's never-steal posture and consistent with the hook's existing fail-open-on-infra-error discipline. Add a test under `tests/` exercising both the self-re-entry pass and the foreign-pipeline deny shapes. Bump the hook's line-2 `# zskills-hook-version:` stamp from `2026.05.0` to today.

**Complexity:** S. **Action now:** /do pr — capture `--pipeline-id` in the shlex walk, read `claim.json` for owner, deny on mismatch; add hook test for foreign-pipeline deny + self-re-entry pass; bump hook version stamp.

### #867 — /run-plan preflight hook-placeholder gate is plugin-lane-blind (wrong path + stale {{...}})

**Labels:** (none) | **Verdict:** NOT FIXED

**Problem.** `skills/run-plan/SKILL.md:737` runs `grep -qE '^(UNIT_TEST_CMD|FULL_TEST_CMD)=.*\{\{' .claude/hooks/block-unsafe-project.sh 2>/dev/null` to detect a "stale `{{...}}` placeholder" misconfiguration. Both pieces are wrong post-#831: (a) the hook on the plugin lane lives at `${CLAUDE_PLUGIN_ROOT}/hooks/block-unsafe-project.sh`, not `.claude/hooks/...` (per `hooks/hooks.json`), so the grep silently no-ops on plugin installs; (b) the current hook template at `hooks/block-unsafe-project.sh.template:579-590` reads `UNIT_TEST_CMD`/`FULL_TEST_CMD` from `.claude/zskills-config.json` at runtime — the body no longer carries `{{…}}` placeholders, so the regex can never match. The prose around the grep (lines 747-775) still frames the failure mode as "stale placeholders" and cites `block-unsafe-project.sh:134-147` (real detection lives at `:611-630`). Net: the gate is structurally dead and gives false reassurance to anyone reading the prose.

**Fix outline.** Replace the grep at `skills/run-plan/SKILL.md:737` with a dual-lane resolver source + a config-read sanity check (same shape the same SKILL.md step 5 already uses three lines later). Rewrite the surrounding prose (lines 747-775) to describe the actual two failure modes the hook fires today — missing/malformed `.claude/zskills-config.json` and Case-C runtime block at `hooks/block-unsafe-project.sh.template:714-729`. Update the stale `block-unsafe-project.sh:134-147` citation to `:611-630`. Bump `metadata.version` on `run-plan` and mirror.

**Complexity:** S. **Action now:** /do pr — swap grep to config-read via dual-lane `zskills-resolve-config.sh` source; rewrite the three-case prose; fix the stale `:134-147` citation; version-bump + mirror.

### #1012 — /manual-testing: user-invocable: false + re-scope to general playwright-cli UI verification

**Labels:** (none) | **Verdict:** NOT YET FIXED

**Problem.** Source confirmed at `skills/manual-testing/SKILL.md` (NOT block-diagram/). Its frontmatter currently has NO `user-invocable` key (lines 1-11), so it defaults to user-typeable and surfaces in the catalog as a peer of /run-plan, /do, etc. — but it's really a support skill /verify-changes leans on for UI verification. Separately, the `description` (lines 4-8) and the entire body are framed as block-diagram-editor-specific (add blocks, connect ports, run simulations, edit parameters), leftover from extraction; the underlying value is general "make playwright-cli behave like a user." `docs/skills/manual-testing.md` mirrors the same block-diagram framing (lines 3, 11, 21-27).

**Fix outline.** In `skills/manual-testing/SKILL.md`: add `user-invocable: false` to frontmatter; rewrite `description` to drop block-diagram language (general playwright-cli "act like a user" support skill, keep "test manually/test in the browser/verify with playwright-cli" triggers); de-block-diagram the body (replace block/port/simulation/parameter sections with general menu-click / canvas click-drag / keyboard / workaround-for-CLI-limits patterns; drop the Common Selectors block-diagram tables + Example Models); bump `metadata.version` (currently 2026.05.31+7061e2) via scripts/skill-content-hash.sh. Rewrite `docs/skills/manual-testing.md` to match. NO fixture updates needed: both conformance tests that touch invocability (`tests/test-skill-conformance.sh` #976 block lines 3469-3505, `tests/test-skill-frontmatter-survival.sh` lines 34-115) are schema-driven — they auto-discover user-invocable:false skills, hardcode no manual-testing string; verified no `(type|re-run) /manual-testing` phrases exist in skills/ so adding the flag won't trip #976. Catalog index files (docs/skills/README.md, docs/DocsRegistry.js, docs/guides/WORKFLOWS.md) use generic "Browser-based manual testing recipes" wording, not the block-diagram string — optional touch, not required.

**Complexity:** M. **Action now:** /do pr — flip frontmatter flag + rewrite description, de-block-diagram SKILL.md body to general "act like a user" playwright-cli patterns, rewrite docs/skills/manual-testing.md, bump metadata.version, run tests/run-all.sh.

### #1002 — Build pipeline: rewrite_dev_urls only covers README.md — source files ship dev-tainted to prod

**Labels:** (none) | **Verdict:** NOT YET FIXED

**Problem.** Both `scripts/build-prod.sh` (line 94) and `scripts/build-plugin-release.sh` (line 141) define an identical `rewrite_dev_urls` function (`zeveck.github.io/zskills-dev` → `zskills.synapticnoise.com` via `sed -i`) but each invokes it on `README.md` ONLY. A repo-wide grep (excluding `.git`/`.claude/` mirror) confirms ~21 shipping source files carry dev URLs unchanged. Confirmed CRITICAL: `skills/zskills-dashboard/scripts/zskills_monitor/static/index.html:13` — dashboard title `href` is the dev Pages URL (404s on click). Confirmed HIGH: `skills/run-plan/SKILL.md:599` — agent-rendered escalation tells users to file issues at `github.com/zeveck/zskills-dev/issues/new` (wrong repo); `docs/guides/INSPECTING_AND_MONITORING.md:113` — demo URL points at dev Pages. Plus 6 `docs/plans/*.md`, 2 `docs/plans/archive/canaries/*.md`, 6 `docs/reports/*.md` (MEDIUM), and CHANGELOG/dogfood (LOW).

**Fix outline.** Phase 1 — in both `scripts/build-prod.sh` and `scripts/build-plugin-release.sh`, replace the single `rewrite_dev_urls README.md` call with a post-strip tree walk over `docs`/`skills`/`README.md`/`CHANGELOG.md` (function is already idempotent via its `grep -q` guard). Phase 2 — promote `rewrite_dev_urls` into `scripts/_lib/finalize-prod-tree.sh` (CONFIRMED EXISTS, 6126 bytes; currently the shared D4-sibling + dev-only-strip finalizer both publishers call) so the two copies can't diverge again. Phase 3 — unify CANARY strip parity: build-prod.sh strips only top-level `$ZSKILLS_PLANS_DIR/CANARY_*.md` + `CANARY_*.md` (line 113), while build-plugin-release.sh does recursive `find "$STAGE" -type f -name '*CANARY*' -delete` (line 158), so `docs/plans/archive/canaries/{CANARY_BATTERY,HANDOFF_CANARY_FAILURE_INJECTION}.md` survive build-prod but are stripped by build-plugin-release — move the strip rule into the shared finalizer. Add 4 test files under `tests/` (none exist yet): `test-prod-tree-no-dev-urls.sh`, `test-build-rewrite-dev-urls.sh`, `test-build-prod-strip-parity.sh`, plus the regression-grep assertions.

**Complexity:** M. **Action now:** /do pr — broaden rewrite to a tree-walk in both builders, promote the function + CANARY strip into `scripts/_lib/finalize-prod-tree.sh`, add the 3-4 test files, coordinate the #984 INSPECTING hand-patch revert.

### #1034 — dashboard collect.py: _read_state_file silently drops issues.skipped (dict)

**Labels:** (none) | **Verdict:** NOT YET FIXED

**Problem.** PR #1030 (849e949) shipped the `Issues × dismiss` UI: `server.py` persists dismissals to `monitor-state.json` under `issues.skipped` (a dict), but the read-half drops them. `collect.py:_read_state_file` builds `issues_out` (lines ~1711-1713) by iterating `issues_raw.items()` keeping ONLY `isinstance(entries, list)` entries, so the `issues.skipped` DICT is silently discarded. Downstream `_read_monitor_skipped(state)` (`collect.py:2287`) reads `state["issues"]["skipped"]` which is now never present, so `_resolve_effective_skip_reason` step-1 live override always falls through to blurb-only rendering — dismissed-issue chips never reflect persisted state. The parallel `plans_skipped` block (lines ~1707-1709) does this correctly via `plans_raw.get("skipped")` + dict copy; the issues block was never made symmetric.

**Fix outline.** In `skills/zskills-dashboard/scripts/zskills_monitor/collect.py` `_read_state_file`, after the `issues_out` for-loop, add a symmetric block preserving `issues_raw["skipped"]` as a dict (mirror the `plans_skipped` pattern). Mirror the edit into `.claude/skills/zskills-dashboard/scripts/zskills_monitor/collect.py`. Add a round-trip test (in `tests/test_zskills_monitor_collect.sh` or `tests/test-fix-issues-claim-collector.py`) that writes a state JSON with `issues.skipped` dict, runs it THROUGH `_read_state_file` (not synthetic state), and asserts the resolved chip reads it as a live override — the existing test at test-fix-issues-claim-collector.py:324-339 bypasses `_read_state_file`, which is why this shipped. Bump `metadata.version` on the source skill.

**Complexity:** S. **Action now:** /do pr — add the symmetric issues.skipped dict-preserve block in collect.py, mirror it, add a round-trip-through-_read_state_file test, version-bump + mirror.
